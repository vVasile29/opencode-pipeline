import { readFile } from "node:fs/promises"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const roles = [
  "context-manager",
  "planner",
  "debater",
  "implementer",
  "reviewer",
  "security-reviewer",
  "tester",
  "linter",
  "commit-msg",
]

const canonicalAgents = ["pipeline", ...roles]
const roleSet = new Set(roles)
const profilePath = resolve(dirname(fileURLToPath(import.meta.url)), "..", ".opencode-pipeline-profile.json")

function validateProfile(profile) {
  if (!profile || typeof profile !== "object" || typeof profile.name !== "string") {
    throw new Error("Invalid OpenCode Pipeline profile")
  }

  const profileAgents = profile.agents
  if (!profileAgents || typeof profileAgents !== "object" || Array.isArray(profileAgents)) {
    throw new Error("OpenCode Pipeline profile must define agents")
  }
  if (Object.keys(profileAgents).sort().join("\n") !== [...canonicalAgents].sort().join("\n")) {
    throw new Error("OpenCode Pipeline profile must define exactly the canonical agents")
  }

  for (const role of canonicalAgents) {
    const settings = profileAgents[role]
    if (!settings || typeof settings !== "object" || Array.isArray(settings)) {
      throw new Error(`Invalid OpenCode Pipeline settings for ${role}`)
    }
    if (typeof settings.model !== "string" || !/^[A-Za-z0-9._:/-]+$/.test(settings.model)) {
      throw new Error(`Invalid OpenCode Pipeline model for ${role}`)
    }
    if (
      settings.variant !== undefined &&
      (typeof settings.variant !== "string" || !/^[A-Za-z0-9._-]+$/.test(settings.variant))
    ) {
      throw new Error(`Invalid OpenCode Pipeline variant for ${role}`)
    }
  }

  return profile
}

function workflowInstruction(sessionID) {
  const safeSessionID = sessionID.replace(/[^A-Za-z0-9_-]/g, "-")
  const path = `.opencode-workflow-state-${safeSessionID}.md`
  return [
    "OpenCode Pipeline runtime state:",
    `- The canonical workflow state file for this pipeline session is \`${path}\` in the project root.`,
    "- Use only this exact file for every phase and handoff.",
    "- Never read or write the legacy unsuffixed `.opencode-workflow-state.md` or another session's state file.",
  ].join("\n")
}

function appendInstruction(text, instruction) {
  return `${text}\n\n${instruction}`
}

export default async (_input, options = {}) => {
  const profile = validateProfile(
    options.profile ?? JSON.parse(await readFile(profilePath, { encoding: "utf8" })),
  )

  return {
    config(config) {
      const configuredAgents = config.agent ?? {}
      for (const role of canonicalAgents) {
        const agent = configuredAgents[role] ?? {}
        agent.model = profile.agents[role].model
        if (profile.agents[role].variant === undefined) delete agent.variant
        else agent.variant = profile.agents[role].variant
        configuredAgents[role] = agent
      }
      config.agent = configuredAgents

      const permission =
        typeof config.permission === "string" ? { "*": config.permission } : (config.permission ?? {})
      const task = typeof permission.task === "string" ? { "*": permission.task } : (permission.task ?? {})

      for (const role of roles) delete task[role]
      for (const role of roles) task[role] = "deny"

      permission.task = task
      config.permission = permission
    },
    async "chat.message"(input, output) {
      if ((input.agent ?? output.message.agent) !== "pipeline") return

      const textPart = [...output.parts].reverse().find((part) => part.type === "text")
      if (!textPart) return
      textPart.text = appendInstruction(textPart.text, workflowInstruction(input.sessionID))
    },
    async "tool.execute.before"(input, output) {
      if (input.tool !== "task") return

      const role = output.args.subagent_type ?? output.args.agent
      if (!roleSet.has(role)) return

      const prompt = typeof output.args.prompt === "string" ? output.args.prompt : ""
      output.args.prompt = appendInstruction(prompt, workflowInstruction(input.sessionID))
    },
  }
}
