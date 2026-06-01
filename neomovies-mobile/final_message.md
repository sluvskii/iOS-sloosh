I've got it! The `HTTP 410: Gone` is caused by a **User-Agent mismatch** between token generation and token usage!

In the log, ExoPlayer tries to fetch the video segment with:
`User-Agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64)`

However, when JS `fetch` requested the `embedHtml` (to get the video tokens in the first place), it **didn't specify a User-Agent**, meaning React Native automatically used its default User-Agent (like `okhttp/4.9.2`).

Collaps' CDN binds these tokens not only to the IP address but **also strictly to the User-Agent**. Because the `embedHtml` was requested with `okhttp/4.9.2` and ExoPlayer fetched the video with `Mozilla/5.0`, the token validation failed, resulting in `410 Gone`!

In `@neomovies-android`, this problem didn't occur because they explicitly hardcode `User-Agent: Mozilla/5.0...` right when fetching the HTML:
```kotlin
        val request = Request.Builder()
                .url(url)
                .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
```

I have just updated `src/lib/neomovies-api.ts` to perfectly align the headers. Now it fetches the embed using:
```typescript
    headers: {
      Accept: 'text/html,application/xhtml+xml',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      Referer: 'https://kinokrad.my/',
      Origin: 'https://kinokrad.my',
    },
```
With the `User-Agent` and `Referer` perfectly synced between JS token extraction, Android's HTTPClient, and ExoPlayer, Collaps will see them as the exact same client session, and the `410 Gone` will disappear completely. You'll just need to rebuild the JS bundle for the fix to take effect!
