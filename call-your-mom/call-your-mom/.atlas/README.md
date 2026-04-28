# Tamagotchi Atlas

Drop sprite-sheet powered Tamagotchis here.

## Add a New Tamagotchi

1. Add your sprite sheet image to `call-your-mom/call-your-mom/Assets.xcassets` as an image set.
2. Copy `manifest.template.json` to `<your-id>.json` in this folder.
3. Fill in your metadata and the sprite sheet frame coordinates.
4. Add `<your-id>` to `registry.json` (without `.json`).

Example `registry.json`:

```json
{
  "manifests": ["spark-kitten", "forest-bun"]
}
```

## Atlas Notes

- `frameSize.width` and `frameSize.height` are frame dimensions in pixels.
- `idleAnimation.fps` controls playback speed.
- `idleAnimation.frames` is the ordered frame sequence used for looping idle animation.
- Each frame entry uses `column` and `row` to pick a cell from the sprite sheet grid.
- `image` must match the asset name in `Assets.xcassets` exactly.
