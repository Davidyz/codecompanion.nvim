local http = require("codecompanion.http")
local config = require("codecompanion.config").config
local schema = require("codecompanion.schema")

---@class CodeCompanion.Tool.Planning: CodeCompanion.Agent.Tool
---@field name string
---@field schema table
---@field cmds table
---@field output table
local M = {}

M.name = "planning"

M.cmds = {
  ---@param agent CodeCompanion.Agent
  ---@param args table { task: string, context: string? }
  ---@param _ table
  ---@param cb fun(info: {status: "success"|"error", data: any})
  function(agent, args, _, cb)
    local task = args.task or "No specific task provided."
    local context = args.context or ""

    local system_prompt = string.format(
      [[
You are an expert software architect and project planner.
Your goal is to create a detailed, step-by-step coding plan based on the user's request and any provided code context.
The plan should be structured logically and be actionable for a developer.

Apart from the single message that follows this system prompt, no other information will be provided.

---
Plan Structure:
## Problem Statement
A clear and concise restatement of the coding task.

## High-Level Plan
A brief overview of the main phases or components of the solution.

## Detailed Steps
Numbered, specific, and actionable steps to implement the solution. 
Break down complex steps and consider common programming practices.

## Tools to Consider
Suggest relevant CodeCompanion tools that could be useful at various stages of the development. Explain briefly why each tool is relevant to a specific step or phase.
%s

## References/Context
If any existing code, documentation, or search results were provided, explain how this context informs the plan. Quote relevant snippets if necessary and refer to their paths.
---

]],
      string.format(
        "Available tools: %s",
        table.concat(
          vim
            .iter(agent.chat.refs)
            :filter(function(item)
              return item.name and item.name == "tool"
            end)
            :map(function(item)
              return vim.inspect(item)
            end)
            :totable(),
          "\n"
        )
      )
    )
    local task_info = "## User Request:\n" .. task .. "\n\n"
    local context_info = ""
    if context ~= "" then
      context_info = "## Provided Context/References:\n```\n" .. context .. "\n```\n\n"
    end

    local adapter = vim.deepcopy(
      require("codecompanion.adapters").resolve((M.opts and M.opts.adapter) or config.strategies.chat.adapter)
    )

    local settings = adapter:map_schema_to_params(schema.get_default(adapter))
    settings.opts = settings.opts or {}
    settings.opts.stream = false

    http.new({ adapter = settings }):request({
      messages = adapter:map_roles({
        { role = config.constants.SYSTEM_ROLE, content = system_prompt },
        { role = config.constants.USER_ROLE, content = task_info .. context_info },
      }),
    }, { ---@param _adapter CodeCompanion.Adapter
      callback = function(_, data, _adapter)
        if data then
          local res = _adapter.handlers.chat_output(_adapter, data)
          if res and res.status == "success" then
            local plan = vim.trim(res.output.content or "")
            if plan then
              return cb({ status = "success", data = plan })
            end
          end
          return cb({ status = "error", data = res.output.content })
        end
        return cb({ status = "error", data = "Failed to retrieve a plan. Go ahead with your own plan." })
      end,
    })
  end,
}

M.schema = {
  type = "function",
  ["function"] = {
    name = "planning",
    description = "Generates a detailed, step-by-step coding plan based on a given task and optional code context. This tool invokes an LLM to act as an expert software architect and project planner, providing a structured and actionable plan. This tool should be called right after a user response, if it's a high-level requirement that isn't trivial to implement. After calling this tool, you may carry out with the task.",
    parameters = {
      type = "object",
      properties = {
        task = {
          type = "string",
          description = [[
The specific coding task or problem for which to generate a plan.

The generated plan will follow this structure:
## Problem Statement: A clear and concise restatement of the coding task.
## High-Level Plan: A brief overview of the main phases or components of the solution.
## Detailed Steps: Numbered, specific, and actionable steps to implement the solution. Break down complex steps and consider common programming practices.
## Tools to Consider: Suggest relevant CodeCompanion tools that could be useful at various stages (e.g., `web_search` for research, `file_search` for locating files, `vectorcode_query` for understanding existing code, `create_file` for new files, `modify_file` for changes, `generate_test` for testing, `run_code` for execution). Explain briefly why each tool is relevant to a specific step or phase.
]],
        },
        context = {
          type = "string",
          description = "Optional relevant code snippets, documentation, tools, or search results that inform the plan. If provided, the plan should explain how this context informs the plan and quote relevant snippets, referring to their paths.",
        },
      },
      required = { "task", "context" },
    },
  },
}

M.output = {
  ---@param self CodeCompanion.Tool.Planning
  ---@param agent CodeCompanion.Agent
  ---@param cmd table The command that was executed
  ---@param stdout table The output from the command
  success = function(self, agent, cmd, stdout)
    agent.chat:add_tool_output(self, stdout[1], "**Planning Tool**: A plan has been generated")
  end,
  ---@param self CodeCompanion.Tool.Planning
  ---@param agent CodeCompanion.Agent
  ---@param cmd table
  ---@param stderr table The error output from the command
  ---@param stdout? table The output from the command
  error = function(self, agent, cmd, stderr, stdout)
    agent.chat:add_tool_output(
      self,
      stderr[1],
      string.format("**Planning Tool**: Failed to generate a plan.\n%s", vim.inspect(stderr))
    )
  end,
}

return M
