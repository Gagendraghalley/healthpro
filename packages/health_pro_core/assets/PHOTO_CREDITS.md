# Photos

| File | Where it shows | Source |
|---|---|---|
| auth/background.jpg | Behind the sign-in, sign-up and code pages (AuthLayout) | Health Pro's own artwork, a bright gym with dumbbells, a water bottle and a towel on the left and blue waves on the right (1672 x 941, the gear on the left clear of the card; saved as progressive JPEG, quality 82; the original is tool/brand/background.png) |

To change it, save another photo over auth/background.jpg (same name). A
wide landscape picture works best (about 1600 x 900): the card covers its
right side on computers (a navy panel on the left fades into it), and phones show it as a banner. Keep it
under about 400 KB, since every sign-in page waits for it:

    cjpeg -quality 82 -progressive -optimize -outfile auth/background.jpg <original>.png
