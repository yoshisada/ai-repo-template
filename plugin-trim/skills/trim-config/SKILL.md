---
name: trim-config
description: Configure the Penpot project connection. Creates or updates .trim-config with project ID, file ID, default page, and component mapping path.
---

# trim-config — Configure Penpot Connection

Set up or update the `.trim-config` file that connects this project to a Penpot project. This is a prerequisite for all other trim skills.

## User Input

```text
$ARGUMENTS
```

## Steps

### 1. Check Existing Configuration

Check if `.trim-config` already exists at the repo root.

```bash
if [ -f .trim-config ]; then
  echo "Existing .trim-config found:"
  cat .trim-config
else
  echo "No .trim-config found — will create one."
fi
```

### 2. Gather Configuration Values

**If `.trim-config` exists**: Display the current values and ask the user which fields they want to update. Accept changes for any subset of fields.

**If `.trim-config` does not exist**: Prompt the user for the required fields:

- **penpot_project_id** (required) — The Penpot project UUID. Found in the Penpot URL: `https://design.penpot.app/#/workspace/<project_id>/...`
- **penpot_file_id** (required) — The Penpot file UUID. Found in the Penpot URL after the project ID.

Set defaults for optional fields:
- **default_page** — leave commented out (syncs all pages)
- **components_file** — `.trim-components.json`
- **framework** — leave commented out (auto-detected)

If the user provided key=value pairs in `$ARGUMENTS`, use those values directly without prompting.

### 3. Write Configuration

Write the `.trim-config` file in key-value format:

```bash
cat > .trim-config << 'TRIMCFG'
# Trim configuration — maps this repo to its Penpot project
# Run /trim-config to update these values interactively

# Required: Penpot project UUID
penpot_project_id = <VALUE>

# Required: Penpot file UUID
penpot_file_id = <VALUE>

# Optional: Default Penpot page name to sync (omit to sync all pages)
# default_page = main

# Optional: Path to component mapping file (default: .trim-components.json)
components_file = .trim-components.json

# Optional: Override auto-detected framework (react, vue, svelte, html)
# framework = react
TRIMCFG
```

Replace `<VALUE>` placeholders with the actual values from the user. Uncomment optional fields if the user provided values for them.

### 4. Validate Configuration

Read back the file and verify required fields are present and not placeholder values:

```bash
PROJ_ID=$(grep '^penpot_project_id' .trim-config | cut -d= -f2 | tr -d ' ')
FILE_ID=$(grep '^penpot_file_id' .trim-config | cut -d= -f2 | tr -d ' ')

if [ -z "$PROJ_ID" ] || [ "$PROJ_ID" = "REPLACE_ME" ]; then
  echo "ERROR: penpot_project_id is missing or still a placeholder"
  exit 1
fi
if [ -z "$FILE_ID" ] || [ "$FILE_ID" = "REPLACE_ME" ]; then
  echo "ERROR: penpot_file_id is missing or still a placeholder"
  exit 1
fi
echo "Configuration valid."
```

### 5. Initialize Component Mapping

If the component mapping file does not exist, create it with an empty array:

```bash
COMP_FILE=$(grep '^components_file' .trim-config | cut -d= -f2 | tr -d ' ')
COMP_FILE=${COMP_FILE:-.trim-components.json}

if [ ! -f "$COMP_FILE" ]; then
  echo '[]' > "$COMP_FILE"
  echo "Created empty component mapping at $COMP_FILE"
else
  echo "Component mapping already exists at $COMP_FILE"
fi
```

### 6. Report

```
Trim configured successfully.

  Project ID:      {penpot_project_id}
  File ID:         {penpot_file_id}
  Default Page:    {default_page or '(all pages)'}
  Components File: {components_file}
  Framework:       {framework or '(auto-detect)'}

  Config:          .trim-config
  Mappings:        {components_file}

Next: Run /trim-pull to generate code from a Penpot design,
      or /trim-push to push existing code components to Penpot.
```

## Rules

- **Required fields must be valid** — reject empty strings, "REPLACE_ME", or obviously invalid UUIDs
- **Preserve comments** — when updating an existing config, keep comment lines intact
- **No Penpot MCP calls** — this skill only manages the local config file
- **Idempotent** — running multiple times updates in place, does not create duplicates
