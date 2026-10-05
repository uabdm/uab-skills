---
name: uab-model-test-glm
description: Test-only skill for checking whether TrueForge switches the session's reasoning model when a skill is invoked. Targets model glm-5.3-flash:cloud. Use only when explicitly asked to "run the GLM model test" or "run uab-model-test-glm". Its action is writing a single haiku about the ocean. Not a production skill — never use it for real work.
model: "glm-5.3-flash:cloud"
---

# UAB Model Test A — GLM

This is test skill **A**. It declares `model: glm-5.3-flash:cloud` in its frontmatter. Its only
purpose is to show whether invoking a skill switches the session's model. The action is
deliberately trivial and different from test skill B (`uab-model-test-local`), so the
transcript makes it obvious which skill ran.

## Do exactly this, nothing more

1. Write one haiku (5-7-5 syllables) about the ocean.
2. On its own line, print the marker:

   ```
   MODEL-TEST-A COMPLETE
   ```

3. Report which model you believe is answering this turn (its name/ID, if you know it). State
   plainly that a model's self-report is weak evidence. The authoritative answer is the model
   shown in TrueForge's session details or trace for this turn.

Do not create files, run commands, or call tools. Just reply.
