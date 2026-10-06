export default function (pi) {
  pi.registerFlag("pi-wrapper-demo", {
    description: "Confirms the pi-nix-wrapper example extension loaded",
    type: "boolean",
    default: false,
  });

  pi.registerCommand("demo", {
    description: "Show which bundled demo resources Pi loaded",
    handler: async (_args, ctx) => {
      const skills = ctx.getSystemPromptOptions().skills ?? [];
      const demoSkillLoaded = skills.some((skill) => skill.name === "pi-wrapper-demo");

      const message = `pi-wrapper-demo-skill-loaded=${demoSkillLoaded}`;
      if (ctx.mode === "tui") {
        ctx.ui.notify(message, demoSkillLoaded ? "info" : "error");
        return;
      }

      console.log(message);
      ctx.shutdown();
    },
  });
}
