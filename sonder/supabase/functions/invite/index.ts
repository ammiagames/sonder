Deno.serve((req: Request) => {
  const url = new URL(req.url);
  const imgParam = url.searchParams.get("img");

  // Validate image URL is from our Supabase Storage only
  let imageURL = "";
  if (imgParam) {
    try {
      const parsed = new URL(decodeURIComponent(imgParam));
      if (parsed.hostname === "qxpkyblruhyrokexihef.supabase.co") {
        imageURL = parsed.href;
      }
    } catch {
      /* ignore malformed */
    }
  }

  const APP_STORE = "https://apps.apple.com/app/sonder";
  const html = `<!DOCTYPE html>
<html lang="en"><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>You're invited to Sonder</title>
  <meta property="og:title" content="You're invited to Sonder" />
  <meta property="og:description" content="Track and share your favorite places with friends" />
  <meta property="og:type" content="website" />
  <meta property="og:url" content="${url.href}" />
  ${
    imageURL
      ? `<meta property="og:image" content="${imageURL}" />
  <meta property="og:image:type" content="image/jpeg" />
  <meta property="og:image:width" content="1080" />
  <meta property="og:image:height" content="1350" />`
      : ""
  }
  <meta name="twitter:card" content="summary_large_image" />
</head><body>
  <h1>You're invited to Sonder</h1>
  <p>Track and share your favorite places with friends.</p>
  <a href="${APP_STORE}">Download Sonder</a>
  <script>window.location.replace("${APP_STORE}");</script>
</body></html>`;

  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=86400",
    },
  });
});
