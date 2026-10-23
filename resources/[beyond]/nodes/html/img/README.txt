Put a GTA V map image here, named map.jpg (or map.png).

It is not included because the map art belongs to Rockstar. A pause-menu
screenshot or tiles exported with OpenIV / CodeWalker work fine.

The image is stretched over the world box the panel draws:
    X  -4000 .. 5000
    Y  -4000 .. 8000
so use the whole map, north up, no borders, roughly 3:4 (e.g. 2048x2730).

If the grid does not line up, change the WORLD constant near the top of the
script in ../index.html. The grid and sectors come from real coordinates, the
picture is only there for landmarks.
