/**
 * Share-link previews for published recipes.
 *
 * WhatsApp (and every other link crawler) fetches the URL's HTML and reads
 * its Open Graph tags — it never runs JavaScript, so the Flutter SPA's
 * per-recipe content is invisible to it. This function sits behind the
 * Hosting rewrite for /r/** and answers with a page whose only job is to
 * carry those tags; a human browser is bounced straight into the app via
 * the hash-fragment form of the same link, which the app already parses.
 *
 * Privacy note, decided deliberately (2026-08-24): the preview exposes the
 * recipe's NAME and COVER PHOTO to anyone holding the link, without an
 * account. The recipe's content stays behind sign-in. The Terms and the
 * Privacy Policy describe exactly this.
 */
const { onRequest } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

initializeApp();

const APP_URL = 'https://app.pintaminis.com';

/** Only ids Firestore can actually mint — everything else is a probe. */
const ID_PATTERN = /^\/r\/([A-Za-z0-9_-]{1,40})$/;

const escapeHtml = (value) =>
  String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/**
 * The page every visitor gets. Crawlers read the tags and stop; browsers
 * follow the redirect into the SPA before a human can read anything here.
 * The redirect targets the HASH form of the link on purpose: it is the
 * format the app has parsed since the first shared recipe, so old links,
 * new links and this bounce all converge on one code path.
 */
const page = ({ id, title, description, imageUrl }) => `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>${escapeHtml(title)}</title>
<meta property="og:type" content="article">
<meta property="og:site_name" content="PintaMinis">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(description)}">
<meta property="og:url" content="${APP_URL}/r/${id}">
${imageUrl ? `<meta property="og:image" content="${escapeHtml(imageUrl)}">
<meta name="twitter:card" content="summary_large_image">` : ''}
<meta http-equiv="refresh" content="0;url=/#/r/${id}">
<script>location.replace('/#/r/${id}');</script>
</head>
<body></body>
</html>
`;

exports.sharePreview = onRequest(
  { region: 'us-central1', maxInstances: 3 },
  async (req, res) => {
    const match = req.path.match(ID_PATTERN);
    if (!match) {
      res.redirect(302, APP_URL);
      return;
    }
    const id = match[1];

    let recipe = null;
    try {
      const snapshot = await getFirestore()
        .collection('publishedRecipes')
        .doc(id)
        .get();
      recipe = snapshot.exists ? snapshot.data() : null;
    } catch (error) {
      // Firestore hiccups must not kill the link: without data the page
      // still bounces the visitor into the app, just with a generic tag.
      console.error(`preview lookup failed for ${id}:`, error);
    }

    // An unshared or unknown recipe gets the same generic page as an
    // outage, and the app decides what to tell the visitor — this function
    // must not become an oracle for probing which ids exist.
    const title = recipe?.name || 'PintaMinis';
    const author = recipe?.authorName || '';
    const description =
      recipe?.description ||
      (author ? `Receta de pintado de ${author}` : 'Recetas de pintado de miniaturas');

    res.set(
      // Five minutes on the shared CDN cache: enough to absorb a link
      // pasted into a busy group, short enough that an unshared recipe's
      // preview dies quickly.
      'Cache-Control',
      'public, max-age=300, s-maxage=300'
    );
    res.status(200).send(
      page({ id, title, description, imageUrl: recipe?.photoUrl || null })
    );
  }
);
