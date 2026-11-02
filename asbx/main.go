// Command asbx generates per-repo sbxenv files from repos.yaml and runs sbx env.
//
// Usage: ./asbx run|create|rm|plan <repo> [--harness NAME] [sbx env flags...]
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"text/template"

	"gopkg.in/yaml.v3"
)

var commands = []string{"run", "create", "rm", "plan"}

const defaultHarness = "copilot"

type repoSpec struct {
	URL        string   `yaml:"url"`
	Path       string   `yaml:"path"`
	EnabledOn  []string `yaml:"enabledOn"`
	DisabledOn []string `yaml:"disabledOn"`
}

// activeOn reports whether the repo is used on this machine; with neither
// list set it is used everywhere.
func (s repoSpec) activeOn(machine string) bool {
	if len(s.EnabledOn) > 0 {
		return slices.Contains(s.EnabledOn, machine)
	}
	return !slices.Contains(s.DisabledOn, machine)
}

type repo struct {
	name string
	url  string
	path string
}

type workspace struct {
	Path  string `yaml:"path"`
	Clone bool   `yaml:"clone"`
}

type mount struct {
	Path     string `yaml:"path"`
	ReadOnly bool   `yaml:"readOnly"`
}

type project struct {
	Name                 string     `yaml:"name"`
	Workspace            workspace  `yaml:"workspace"`
	AdditionalWorkspaces []mount    `yaml:"additionalWorkspaces,omitempty"`
	Lifecycle            *lifecycle `yaml:"lifecycle,omitempty"`
}

type lifecycle struct {
	PostCreate []hostCommand `yaml:"postCreate"`
}

type hostCommand struct {
	Name    string `yaml:"name"`
	Command string `yaml:"command"`
}

// generatedFiles is what asbx renders for a harness and how it reaches the sandbox.
type generatedFiles struct {
	mounts []string
	links  []hostCommand
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if exe, err = filepath.EvalSymlinks(exe); err != nil {
		return err
	}
	here := filepath.Dir(exe)

	args := os.Args[1:]
	if len(args) == 1 && args[0] == "sync" {
		return syncAll(here)
	}
	if len(args) < 2 || !slices.Contains(commands, args[0]) {
		return usage(here)
	}
	cmd, name := args[0], args[1]
	harness, extra, err := parseHarness(args[2:])
	if err != nil {
		return err
	}
	if !slices.Contains(listHarnesses(here), harness) {
		return fmt.Errorf("unknown harness: %s (available: %s)", harness, strings.Join(listHarnesses(here), ", "))
	}

	project := filepath.Join(here, "projects", harness+"-"+name+".yaml")
	// rm must keep working even when the config is broken or out of date.
	if cmd != "rm" {
		repos, err := loadRepos(reposFile(here))
		if err != nil {
			return err
		}
		if !slices.ContainsFunc(repos, func(r repo) bool { return r.name == name }) {
			return fmt.Errorf("unknown repo: %s (add it to repos.yaml, then run ./asbx sync)", name)
		}
		if err := checkStamp(here); err != nil {
			return err
		}
	}
	if _, err := os.Stat(project); err != nil {
		return fmt.Errorf("%s not found: run ./asbx sync", project)
	}

	bin, err := exec.LookPath("sbx")
	if err != nil {
		return err
	}
	files := []string{
		filepath.Join(here, "shared", "base.sbxenv.yaml"),
		filepath.Join(here, "harnesses", harness, "sbxenv.yaml"),
		project,
	}
	hcfg, err := loadHarness(here, harness)
	if err != nil {
		return err
	}
	var envArgs []string
	// Harnesses with instructions.target get a symlink instead of the env-arg.
	if hcfg.Instructions.Target == "" {
		envArgs = []string{"--env-arg", "instructions=" + instructionsDir(here, harness)}
	}

	argv := append(append([]string{"sbx", "env", cmd}, envArgs...), extra...)
	return syscall.Exec(bin, append(argv, files...), os.Environ())
}

func usage(here string) error {
	fmt.Printf("usage: ./asbx sync\n       ./asbx %s <repo> [--harness NAME] [sbx env flags...]\n", strings.Join(commands, "|"))
	repos, err := loadRepos(reposFile(here))
	if err != nil {
		return err
	}
	fmt.Println("repos:")
	for _, r := range repos {
		missing := ""
		if _, err := os.Stat(r.path); err != nil {
			missing = "  (missing, run ./asbx sync)"
		}
		fmt.Printf("  %-12s %s%s\n", r.name, r.path, missing)
	}
	fmt.Printf("harnesses: %s (default %s)\n", strings.Join(listHarnesses(here), ", "), defaultHarness)
	if err := checkStamp(here); err != nil {
		fmt.Println(err)
	}
	os.Exit(1)
	return nil
}

// syncAll clones missing repos and generates everything for every harness.
func syncAll(here string) error {
	repos, err := loadRepos(reposFile(here))
	if err != nil {
		return err
	}
	for i := range repos {
		if err := ensureCloned(&repos[i]); err != nil {
			return err
		}
	}
	for _, harness := range listHarnesses(here) {
		hcfg, err := loadHarness(here, harness)
		if err != nil {
			return err
		}
		instrDir, err := writeInstructions(here, harness, hcfg)
		if err != nil {
			return err
		}
		gen := generatedFiles{mounts: []string{instrDir}}
		if t := hcfg.Instructions.Target; t != "" {
			if !filepath.IsAbs(t) {
				return fmt.Errorf("harness %s: instructions.target must be absolute", harness)
			}
			gen.links = append(gen.links, hostCommand{
				Name: "Link instructions",
				Command: fmt.Sprintf(`sbx exec "$SBX_SANDBOX_NAME" sh -c 'mkdir -p %s && ln -sfn %s %s'`,
					filepath.Dir(t), filepath.Join(instrDir, hcfg.Instructions.File), t),
			})
		}
		if err := writeLSP(here, harness, hcfg, &gen); err != nil {
			return err
		}
		if err := writeSkills(here, harness, hcfg, repos, &gen); err != nil {
			return err
		}
		if err := writeHooks(here, harness, hcfg, &gen); err != nil {
			return err
		}
		if err := writeProjects(filepath.Join(here, "projects"), harness, gen, repos); err != nil {
			return err
		}
		fmt.Printf("synced %s: %d repos\n", harness, len(repos))
	}
	sum, err := configHash(here)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(here, "generated", ".stamp"), []byte(sum+"\n"), 0o644)
}

func instructionsDir(here, harness string) string {
	return filepath.Join(here, "generated", harness, "instructions")
}

// configHash covers every input sync reads, so run can tell when it is stale.
func configHash(here string) (string, error) {
	h := sha256.New()
	add := func(path string) error {
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(here, path)
		fmt.Fprintf(h, "%s\x00%d\x00", rel, len(data))
		h.Write(data)
		return nil
	}
	if err := add(reposFile(here)); err != nil {
		return "", err
	}
	for _, dir := range []string{"shared", "harnesses"} {
		err := filepath.WalkDir(filepath.Join(here, dir), func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return err
			}
			return add(path)
		})
		if err != nil {
			return "", err
		}
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func checkStamp(here string) error {
	want, err := configHash(here)
	if err != nil {
		return err
	}
	got, err := os.ReadFile(filepath.Join(here, "generated", ".stamp"))
	if err != nil || strings.TrimSpace(string(got)) != want {
		return fmt.Errorf("config changed since the last sync: run ./asbx sync")
	}
	return nil
}

func loadRepos(file string) ([]repo, error) {
	data, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	var cfg struct {
		Root  string    `yaml:"root"`
		Repos yaml.Node `yaml:"repos"`
	}
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("%s: %w", file, err)
	}
	if cfg.Root == "" {
		cfg.Root = "~/Code"
	}
	root, err := absPath(cfg.Root, "")
	if err != nil {
		return nil, err
	}

	machine, err := machineName(filepath.Dir(file))
	if err != nil {
		return nil, err
	}

	// Decode via the mapping node to keep the order from the file.
	var repos []repo
	content := cfg.Repos.Content
	for i := 0; i+1 < len(content); i += 2 {
		name := content[i].Value
		var spec repoSpec
		if err := content[i+1].Decode(&spec); err != nil {
			return nil, fmt.Errorf("repo %s: %w", name, err)
		}
		if len(spec.EnabledOn) > 0 && len(spec.DisabledOn) > 0 {
			return nil, fmt.Errorf("repo %s: set enabledOn or disabledOn, not both", name)
		}
		if !spec.activeOn(machine) {
			continue
		}
		p := spec.Path
		if p == "" {
			p = name
		}
		path, err := absPath(p, root)
		if err != nil {
			return nil, err
		}
		repos = append(repos, repo{name: name, url: spec.URL, path: path})
	}
	return repos, nil
}

// absPath expands ~ and resolves relative paths against base.
func absPath(p, base string) (string, error) {
	if p == "~" || strings.HasPrefix(p, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		p = filepath.Join(home, p[1:])
	}
	if !filepath.IsAbs(p) && base != "" {
		p = filepath.Join(base, p)
	}
	return filepath.Abs(p)
}

func ensureCloned(r *repo) error {
	if _, err := os.Stat(r.path); err != nil {
		if !os.IsNotExist(err) {
			return err
		}
		if r.url == "" {
			return fmt.Errorf("%s: %s does not exist and no url is set", r.name, r.path)
		}
		if err := os.MkdirAll(filepath.Dir(r.path), 0o755); err != nil {
			return err
		}
		c := exec.Command("git", "clone", r.url, r.path)
		c.Stdout, c.Stderr = os.Stdout, os.Stderr
		if err := c.Run(); err != nil {
			return fmt.Errorf("clone %s: %w", r.name, err)
		}
	}
	if real, err := filepath.EvalSymlinks(r.path); err == nil {
		r.path = real
	}
	return nil
}

func writeProjects(dir, harness string, gen generatedFiles, repos []repo) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	old, _ := filepath.Glob(filepath.Join(dir, harness+"-*.yaml"))
	for _, f := range old {
		if err := os.Remove(f); err != nil {
			return err
		}
	}
	for _, r := range repos {
		p := project{
			Name:      harness + "-" + r.name,
			Workspace: workspace{Path: r.path, Clone: true},
		}
		for _, o := range repos {
			if o.name != r.name {
				p.AdditionalWorkspaces = append(p.AdditionalWorkspaces, mount{Path: o.path, ReadOnly: true})
			}
		}
		for _, m := range gen.mounts {
			p.AdditionalWorkspaces = append(p.AdditionalWorkspaces, mount{Path: m, ReadOnly: true})
		}
		if len(gen.links) > 0 {
			p.Lifecycle = &lifecycle{PostCreate: gen.links}
		}
		var b strings.Builder
		b.WriteString("# generated by ./asbx from repos.yaml\n")
		enc := yaml.NewEncoder(&b)
		enc.SetIndent(2)
		if err := enc.Encode(p); err != nil {
			return err
		}
		if err := enc.Close(); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(dir, harness+"-"+r.name+".yaml"), []byte(b.String()), 0o644); err != nil {
			return err
		}
	}
	return nil
}

// parseHarness pulls --harness NAME / --harness=NAME out of args; the rest goes to sbx env.
func parseHarness(args []string) (string, []string, error) {
	harness := defaultHarness
	var rest []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--harness":
			if i+1 >= len(args) {
				return "", nil, fmt.Errorf("--harness needs a value")
			}
			harness = args[i+1]
			i++
		case strings.HasPrefix(a, "--harness="):
			harness = strings.TrimPrefix(a, "--harness=")
		default:
			rest = append(rest, a)
		}
	}
	return harness, rest, nil
}

func listHarnesses(here string) []string {
	matches, _ := filepath.Glob(filepath.Join(here, "harnesses", "*", "sbxenv.yaml"))
	var names []string
	for _, m := range matches {
		names = append(names, filepath.Base(filepath.Dir(m)))
	}
	return names
}

type harnessConfig struct {
	Instructions struct {
		File   string `yaml:"file"`
		Header string `yaml:"header"`
		Target string `yaml:"target"`
	} `yaml:"instructions"`
	LSP *struct {
		Format string `yaml:"format"`
		File   string `yaml:"file"`
		Target string `yaml:"target"`
	} `yaml:"lsp"`
	Skills *struct {
		Target string `yaml:"target"`
		Layout string `yaml:"layout"` // "" (skills/<name>/SKILL.md) or "flat" (<name>.md)
	} `yaml:"skills"`
	Hooks *struct {
		Target string `yaml:"target"`
	} `yaml:"hooks"`
}

func loadHarness(here, harness string) (harnessConfig, error) {
	var cfg harnessConfig
	data, err := os.ReadFile(filepath.Join(here, "harnesses", harness, "harness.yaml"))
	if err != nil {
		return cfg, err
	}
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return cfg, fmt.Errorf("harness %s: %w", harness, err)
	}
	return cfg, nil
}

// writeInstructions renders shared/workflow.md in the format the harness reads
// and returns the directory holding it.
func writeInstructions(here, harness string, cfg harnessConfig) (string, error) {
	if cfg.Instructions.File == "" {
		return "", fmt.Errorf("harness %s: instructions.file is not set", harness)
	}
	if filepath.Base(cfg.Instructions.File) != cfg.Instructions.File {
		return "", fmt.Errorf("harness %s: instructions.file must be a plain file name", harness)
	}

	workflow, err := os.ReadFile(filepath.Join(here, "shared", "workflow.md"))
	if err != nil {
		return "", err
	}

	dir := filepath.Join(here, "generated", harness, "instructions")
	// Update in place: a running sandbox has this directory bind-mounted.
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	stale, _ := filepath.Glob(filepath.Join(dir, "*"))
	for _, f := range stale {
		if filepath.Base(f) != cfg.Instructions.File {
			if err := os.RemoveAll(f); err != nil {
				return "", err
			}
		}
	}
	header := cfg.Instructions.Header
	if header != "" && !strings.HasSuffix(header, "\n") {
		header += "\n"
	}
	if header != "" {
		header += "\n"
	}
	content := header + "<!-- generated by ./asbx from shared/workflow.md -->\n\n" + string(workflow)
	return dir, os.WriteFile(filepath.Join(dir, cfg.Instructions.File), []byte(content), 0o644)
}

type lspServer struct {
	Command    string            `yaml:"command"`
	Args       []string          `yaml:"args"`
	Extensions map[string]string `yaml:"extensions"`
}

// writeLSP renders shared/lsp.yaml in the harness's format and arranges for it
// to be mounted and linked to where the agent reads it.
func writeLSP(here, harness string, cfg harnessConfig, gen *generatedFiles) error {
	if cfg.LSP == nil {
		return nil
	}
	l := cfg.LSP
	if l.File == "" || filepath.Base(l.File) != l.File || !filepath.IsAbs(l.Target) {
		return fmt.Errorf("harness %s: lsp needs a plain file name and an absolute target", harness)
	}
	var src struct {
		Servers map[string]lspServer `yaml:"servers"`
	}
	data, err := os.ReadFile(filepath.Join(here, "shared", "lsp.yaml"))
	if err != nil {
		return err
	}
	if err := yaml.Unmarshal(data, &src); err != nil {
		return fmt.Errorf("shared/lsp.yaml: %w", err)
	}

	var out []byte
	switch l.Format {
	case "copilot":
		type copilotServer struct {
			Command        string            `json:"command"`
			Args           []string          `json:"args,omitempty"`
			FileExtensions map[string]string `json:"fileExtensions"`
		}
		servers := map[string]copilotServer{}
		for name, s := range src.Servers {
			servers[name] = copilotServer{Command: s.Command, Args: s.Args, FileExtensions: s.Extensions}
		}
		out, err = json.MarshalIndent(map[string]any{"lspServers": servers}, "", "  ")
		if err != nil {
			return err
		}
	default:
		return fmt.Errorf("harness %s: unknown lsp format %q", harness, l.Format)
	}

	dir := filepath.Join(here, "generated", harness, "lsp")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	file := filepath.Join(dir, l.File)
	// Rewritten in place so a running sandbox's symlink keeps pointing at it.
	if err := os.WriteFile(file, append(out, '\n'), 0o644); err != nil {
		return err
	}
	gen.mounts = append(gen.mounts, dir)
	gen.links = append(gen.links, hostCommand{
		Name: "Link LSP config",
		Command: fmt.Sprintf(`sbx exec "$SBX_SANDBOX_NAME" sh -c 'mkdir -p %s && ln -sfn %s %s'`,
			filepath.Dir(l.Target), file, l.Target),
	})
	return nil
}

type skillData struct {
	Repos []skillRepo
}

type skillRepo struct {
	Name string
	Path string
}

// writeSkills renders shared/skills/* (as text/template, filled from repos.yaml)
// into generated/<harness>/skills and links that directory to where the agent
// reads skills.
func writeSkills(here, harness string, cfg harnessConfig, repos []repo, gen *generatedFiles) error {
	if cfg.Skills == nil {
		return nil
	}
	if !filepath.IsAbs(cfg.Skills.Target) {
		return fmt.Errorf("harness %s: skills.target must be absolute", harness)
	}
	data := skillData{}
	for _, r := range repos {
		data.Repos = append(data.Repos, skillRepo{Name: r.name, Path: r.path})
	}

	src := filepath.Join(here, "shared", "skills")
	dst := filepath.Join(here, "generated", harness, "skills")
	switch cfg.Skills.Layout {
	case "":
		if err := renderTree(src, dst, data); err != nil {
			return err
		}
	case "flat":
		if err := renderFlatSkills(src, dst, data); err != nil {
			return err
		}
	default:
		return fmt.Errorf("harness %s: unknown skills layout %q", harness, cfg.Skills.Layout)
	}

	gen.mounts = append(gen.mounts, dst)
	gen.links = append(gen.links, hostCommand{
		Name: "Link skills",
		Command: fmt.Sprintf(`sbx exec "$SBX_SANDBOX_NAME" sh -c 'mkdir -p %s && rm -rf %s && ln -sfn %s %s'`,
			filepath.Dir(cfg.Skills.Target), cfg.Skills.Target, dst, cfg.Skills.Target),
	})
	return nil
}

// writeHooks renders harnesses/<harness>/hooks/* (as text/template, with
// {{.Shared}} set to the shared/ dir) into generated/<harness>/hooks and links
// that directory to where the agent reads hooks.
func writeHooks(here, harness string, cfg harnessConfig, gen *generatedFiles) error {
	if cfg.Hooks == nil {
		return nil
	}
	if !filepath.IsAbs(cfg.Hooks.Target) {
		return fmt.Errorf("harness %s: hooks.target must be absolute", harness)
	}
	src := filepath.Join(here, "harnesses", harness, "hooks")
	dst := filepath.Join(here, "generated", harness, "hooks")
	data := struct{ Shared string }{Shared: filepath.Join(here, "shared")}
	if err := renderTree(src, dst, data); err != nil {
		return err
	}
	gen.mounts = append(gen.mounts, dst)
	gen.links = append(gen.links, hostCommand{
		Name: "Link hooks",
		Command: fmt.Sprintf(`sbx exec "$SBX_SANDBOX_NAME" sh -c 'mkdir -p %s && rm -rf %s && ln -sfn %s %s'`,
			filepath.Dir(cfg.Hooks.Target), cfg.Hooks.Target, dst, cfg.Hooks.Target),
	})
	return nil
}

// renderTree renders every file under src as a text/template into dst and
// removes files in dst that no longer exist in src. dst is updated in place
// because a running sandbox has it bind-mounted.
func renderTree(src, dst string, data any) error {
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	want := map[string]bool{}
	err := filepath.WalkDir(src, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		out := filepath.Join(dst, rel)
		want[out] = true
		if d.IsDir() {
			return os.MkdirAll(out, 0o755)
		}
		raw, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		tmpl, err := template.New(rel).Option("missingkey=error").Parse(string(raw))
		if err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		var b bytes.Buffer
		if err := tmpl.Execute(&b, data); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		return os.WriteFile(out, b.Bytes(), 0o644)
	})
	if err != nil {
		return err
	}
	var stale []string
	_ = filepath.WalkDir(dst, func(path string, d os.DirEntry, err error) error {
		if err == nil && path != dst && !want[path] {
			stale = append(stale, path)
			if d.IsDir() {
				return filepath.SkipDir
			}
		}
		return nil
	})
	for _, p := range stale {
		if err := os.RemoveAll(p); err != nil {
			return err
		}
	}
	return nil
}

// renderFlatSkills renders src/<name>/SKILL.md to dst/<name>.md for agents
// that only load flat skill files. Skills with other files are rejected since
// those files would be unreachable.
func renderFlatSkills(src, dst string, data any) error {
	tmp, err := os.MkdirTemp("", "asbx-skills-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	if err := renderTree(src, tmp, data); err != nil {
		return err
	}
	entries, err := os.ReadDir(tmp)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	want := map[string]bool{}
	for _, e := range entries {
		if !e.IsDir() {
			return fmt.Errorf("shared/skills/%s: flat layout expects only <name>/SKILL.md", e.Name())
		}
		files, err := os.ReadDir(filepath.Join(tmp, e.Name()))
		if err != nil {
			return err
		}
		if len(files) != 1 || files[0].Name() != "SKILL.md" {
			return fmt.Errorf("shared/skills/%s: flat layout supports only a single SKILL.md", e.Name())
		}
		b, err := os.ReadFile(filepath.Join(tmp, e.Name(), "SKILL.md"))
		if err != nil {
			return err
		}
		name := e.Name() + ".md"
		want[name] = true
		if err := os.WriteFile(filepath.Join(dst, name), b, 0o644); err != nil {
			return err
		}
	}
	// Remove stale entries in place: a running sandbox has dst bind-mounted.
	old, err := os.ReadDir(dst)
	if err != nil {
		return err
	}
	for _, e := range old {
		if !want[e.Name()] {
			if err := os.RemoveAll(filepath.Join(dst, e.Name())); err != nil {
				return err
			}
		}
	}
	return nil
}

// reposFile lives in the dotty root so other tools (wezterm) can share it.
func reposFile(here string) string {
	return filepath.Join(here, "..", "repos.yaml")
}

// machineName reads the gitignored .machine file next to repos.yaml.
// Without it, repos with enabledOn are skipped and disabledOn never matches.
func machineName(dir string) (string, error) {
	data, err := os.ReadFile(filepath.Join(dir, ".machine"))
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}
