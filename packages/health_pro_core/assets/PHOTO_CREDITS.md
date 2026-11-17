# Photos

| File | Where it shows | Source |
|---|---|---|
| auth/background.jpg | Behind the sign-in, sign-up and code pages (AuthLayout) | Health Pro's own artwork, "Dynamic Bhutan Sports Panorama" (1672 x 941, saved as progressive JPEG, quality 82) |

To change it, save another photo over auth/background.jpg (same name). A
wide landscape picture works best (about 1600 x 900): the card covers its
right third on computers, and phones show it whole as a banner. Keep it
under about 400 KB, since every sign-in page waits for it:

    cjpeg -quality 82 -progressive -optimize -outfile auth/background.jpg <original>.png
