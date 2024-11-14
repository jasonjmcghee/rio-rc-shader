# Global Illumination

Add:

```toml
[renderer]
filters = [
  "/path/to/rc/rc.slangp"
]
```

And replace the `/path/to` with the path to it.

- Ensure `opacity` is less than 0.99 for the editor.
- To enable sky radiance (white look) modify `rc5.slang` to have `ENABLE_SUN = true`
- To improve performance, set `BILINEAR_FIX_ENABLED = false` in all rc[0-5].slang files.

from a code perspective, these are wildly ugly shaders and i'm sorry.

![image](https://github.com/user-attachments/assets/4a4ad515-cdea-48c4-b44b-4505c66c06b6)


# Videos


https://github.com/user-attachments/assets/d38916a2-1652-4280-a5c4-587d62e8cd91


https://github.com/user-attachments/assets/6bbbff94-c996-4004-a860-e64a1429a104


https://github.com/user-attachments/assets/48f2a19d-6e37-420c-be98-016daeb96572
