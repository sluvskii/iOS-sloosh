export interface GitHubRelease {
  tag_name: string;
  name: string;
  body: string;
  prerelease: boolean;
  assets: {
    name: string;
    size: number;
    browser_download_url: string;
  }[];
  published_at: string;
}

const DEFAULT_REPO = 'Neo-Open-Source/neomovies-mobile';

export async function fetchLatestRelease(
  repo: string = DEFAULT_REPO,
  includePrerelease: boolean = false
): Promise<GitHubRelease | null> {
  try {
    const url = `https://api.github.com/repos/${repo}/releases`;
    const response = await fetch(url, {
      headers: { Accept: 'application/vnd.github.v3+json' },
    });

    if (!response.ok) return null;

    const releases: GitHubRelease[] = await response.json();
    const filtered = includePrerelease
      ? releases
      : releases.filter((r) => !r.prerelease);

    return filtered[0] || null;
  } catch {
    return null;
  }
}

export function compareVersions(current: string, latest: string): number {
  const cleanCurrent = current.replace(/^v/, '').split('-')[0];
  const cleanLatest = latest.replace(/^v/, '').split('-')[0];

  const currentParts = cleanCurrent.split('.').map(Number);
  const latestParts = cleanLatest.split('.').map(Number);

  for (let i = 0; i < Math.max(currentParts.length, latestParts.length); i++) {
    const a = currentParts[i] || 0;
    const b = latestParts[i] || 0;
    if (a < b) return -1;
    if (a > b) return 1;
  }

  return 0;
}

export function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
}

export function parseChangelog(body: string): string[] {
  const lines = body.split('\n').filter((line) => line.trim());
  const changes: string[] = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith('-') || trimmed.startsWith('*')) {
      changes.push(trimmed.substring(1).trim());
    } else if (trimmed.match(/^[a-f0-9]{6,7}:/)) {
      // Commit-style: "abc123: message"
      const colonIndex = trimmed.indexOf(':');
      if (colonIndex > 0) {
        changes.push(trimmed.substring(colonIndex + 1).trim());
      }
    }
  }

  return changes.length > 0 ? changes : [body];
}
