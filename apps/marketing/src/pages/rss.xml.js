// Audit Ch10-W106: RSS feed for the blog. Pulls from the same content
// collection as the listing page so a new post automatically appears in
// the feed without manual edits.
import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';

export async function GET(context) {
  const posts = await getCollection('blog');
  return rss({
    title: 'HavenKeep blog',
    description:
      'Tips, guides, and consumer-protection writing on warranties, receipts, and home maintenance.',
    site: context.site,
    items: posts
      .map((p) => ({
        title: p.data.title,
        description: p.data.excerpt,
        pubDate: p.data.date,
        link: `/blog/${p.slug}/`,
        categories: [p.data.category],
      }))
      .sort((a, b) => b.pubDate.getTime() - a.pubDate.getTime()),
    stylesheet: false,
    customData: '<language>en-us</language>',
  });
}
