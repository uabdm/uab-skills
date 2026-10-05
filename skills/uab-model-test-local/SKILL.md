---
name: uab-model-test-local
description: Test-only skill for checking whether TrueForge switches the session's reasoning model when a skill is invoked. Targets model uablocalai-reasoning. Use only when explicitly asked to "run the local model test" or "run uab-model-test-local". Its action is listing the prime numbers below 50. Not a production skill — never use it for real work.
model: "uablocalai-reasoning"
---

# UAB Model Test B — Local reasoning model

This is test skill **B**. It declares `model: uablocalai-reasoning` in its frontmatter. Its only
purpose is to show whether invoking a skill switches the session's model. The action is
deliberately trivial and different from test skill A (`uab-model-test-glm`), so the transcript
makes it obvious which skill ran.

## Do exactly this, nothing more

1. List every prime number below 50, comma-separated, on one line.
2. On its own line, print the marker:

   ```
   MODEL-TEST-B COMPLETE
   ```

3. Report which model you believe is answering this turn (its name/ID, if you know it). State
   plainly that a model's self-report is weak evidence. The authoritative answer is the model
   shown in TrueForge's session details or trace for this turn.

Do not create files, run commands, or call tools. Just reply.
