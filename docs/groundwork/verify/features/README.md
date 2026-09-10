# Feature map

What this repository does, from the outside. One file per property that has to hold, each
answering the same four questions, short enough that an agent can check it without opening
`control`.

A "feature" here is not a skill - there are 45 of those and they do not need 45 files. It is
a property that must hold across all of them, and that nothing else in the repository
enforces.

## Sweep order

Top to bottom is the regression order.

1. [Skill identity](0001-skill-identity.md) - the name an agent invokes resolves
2. [Skill registration](0002-skill-registration.md) - a published skill is findable
3. [Private skills stay private](0003-private-skills-stay-private.md) - the inverse
4. [Skill-owned tests](0004-skill-owned-tests.md) - a skill that ships a test still passes it

## Conventions

- One property per file. Behaviour, never implementation.
- Update the entry in the same change that alters the behaviour. A map that drifts is worse
  than no map, because it is trusted.
- A check that cannot fail is not a check. Every entry below names how to break it, and every
  one of those was run.
