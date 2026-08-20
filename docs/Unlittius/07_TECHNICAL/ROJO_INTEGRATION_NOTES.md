# ROJO INTEGRATION NOTES

Claude should inspect:
- `default.project.json`
- nested `*.project.json`
- `src/`
- server/client/shared folder conventions
- existing boss/enemy asset strategy

## Do not blindly create this exact structure

The included scaffold files are references.

Claude should map them onto the repository's existing architecture.

## If visual model is created procedurally from Luau

Good for:
- rapid iteration;
- user mostly works through VS Code/Rojo;
- easy parameter tuning.

But final recommendation:
- once visual geometry stabilizes, consider storing a baked Roblox model/rig if the project already supports asset/model source files.

## If model is Studio-authored

Keep:
- exact Motor6D names matching animation rig;
- attachments named consistently;
- animation IDs/config under source control;
- gameplay code in Rojo.

## Asset IDs

Do not hardcode fake IDs.

Use config entries:
```lua
Animations = {
    Idle = "rbxassetid://REPLACE_ME",
}
```

Same rule for sounds.

Claude should provide a single manifest of missing asset IDs after implementation so the user can paste IDs once the assets are uploaded.
