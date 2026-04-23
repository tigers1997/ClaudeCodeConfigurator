{
  "$schema": "https://code.claude.com/schema/mcp.json",
  "//": "Project-scoped MCP config. Commit this to share with future-you (or teammates).",
  "//2": "Scopes in order of precedence: local > project > user.",
  "mcpServers": {
    "//filesystem": "Read/write files in a sandboxed path. Uncomment and set ALLOWED_PATH.",
    "// filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/ABSOLUTE/ALLOWED/PATH"]
    },

    "//git": "Local git operations beyond what Bash allows.",
    "// git": {
      "command": "uvx",
      "args": ["mcp-server-git", "--repository", "."]
    },

    "//github": "GitHub issues, PRs, and repos. Requires GITHUB_TOKEN env.",
    "// github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
      }
    },

    "//playwright": "Browser automation — good for UI regression checks.",
    "// playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    },

    "//context7": "Live library docs lookup.",
    "// context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    }
  }
}
