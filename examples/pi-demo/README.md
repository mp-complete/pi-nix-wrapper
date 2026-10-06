# Runnable Pi wrapper example

This directory contains the resources used by `packages.<system>.example`:

- an extension that registers `--pi-wrapper-demo` and `/demo`;
- a `pi-wrapper-demo` skill;
- a `/demo-review` prompt template;
- a complete `pi-wrapper-demo` theme;
- appended wrapper instructions.

Run it from the repository root:

```console
nix run .#example
```

Inside Pi, run `/demo` to verify the extension and skill, or `/demo-review` to
expand the bundled prompt template. The wrapper keeps normal project context
file discovery enabled but disables ambient discovery for the four resource
kinds demonstrated here.
