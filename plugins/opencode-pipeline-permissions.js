export default async () => ({
  config(config) {
    const roles = [
      "planner",
      "debater",
      "implementer",
      "reviewer",
      "security-reviewer",
      "tester",
      "linter",
      "commit-msg",
    ]

    const permission =
      typeof config.permission === "string" ? { "*": config.permission } : (config.permission ?? {})
    const task = typeof permission.task === "string" ? { "*": permission.task } : (permission.task ?? {})

    for (const role of roles) task[role] = "deny"

    permission.task = task
    config.permission = permission
  },
})
