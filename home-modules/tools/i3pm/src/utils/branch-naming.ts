/**
 * Branch Naming Utilities
 * Feature 077: Git Worktree Project Management
 *
 * Mirrors speckit's create-new-feature.sh logic for consistent branch naming
 */

import { execGit } from "./git.ts";

// Common stop words to filter out (matches speckit)
const STOP_WORDS = new Set([
  "i", "a", "an", "the", "to", "for", "of", "in", "on", "at", "by", "with",
  "from", "is", "are", "was", "were", "be", "been", "being", "have", "has",
  "had", "do", "does", "did", "will", "would", "should", "could", "can", "may",
  "might", "must", "shall", "this", "that", "these", "those", "my", "your",
  "our", "their", "want", "need", "add", "get", "set"
]);

/**
 * Generate a short branch suffix from a feature description
 * Filters stop words and keeps 3-4 meaningful words
 */
export function generateBranchSuffix(description: string): string {
  // Convert to lowercase and extract words
  const cleanedWords = description
    .toLowerCase()
    .replace(/[^a-z0-9]/g, " ")
    .split(/\s+/)
    .filter(word => word.length > 0);

  // Filter meaningful words
  const meaningfulWords: string[] = [];
  for (const word of cleanedWords) {
    // Skip stop words
    if (STOP_WORDS.has(word)) continue;

    // Keep words >= 3 chars, or short words that appear uppercase in original (acronyms)
    if (word.length >= 3) {
      meaningfulWords.push(word);
    } else if (description.includes(word.toUpperCase())) {
      // Likely an acronym
      meaningfulWords.push(word);
    }
  }

  // Take first 3-4 meaningful words
  if (meaningfulWords.length > 0) {
    const maxWords = meaningfulWords.length === 4 ? 4 : 3;
    return meaningfulWords.slice(0, maxWords).join("-");
  }

  // Fallback: just clean up the original description
  return description
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .split("-")
    .filter(w => w.length > 0)
    .slice(0, 3)
    .join("-");
}

/**
 * Find the next available feature number by checking:
 * 1. Remote branches (ALL numbered branches)
 * 2. Local branches (ALL numbered branches)
 * 3. Specs directories (ALL numbered directories)
 *
 * Uses GLOBAL numbering - finds highest number across all branches,
 * not just branches with matching suffix.
 */
export async function findNextFeatureNumber(
  _shortName: string,  // Unused but kept for API compatibility
  repoRoot: string
): Promise<number> {
  const numbers: number[] = [];

  // 1. Fetch latest from remotes (ignore errors if no remotes)
  try {
    await execGit(["fetch", "--all", "--prune"], repoRoot);
  } catch {
    // Ignore fetch errors (e.g., no remotes configured)
  }

  // 2. Check ALL remote branches with numeric prefix
  try {
    const remoteOutput = await execGit(
      ["ls-remote", "--heads", "origin"],
      repoRoot
    );
    const remotePattern = /refs\/heads\/(\d+)-/gm;
    let match;
    while ((match = remotePattern.exec(remoteOutput)) !== null) {
      numbers.push(parseInt(match[1], 10));
    }
  } catch {
    // No remotes or no matching branches
  }

  // 3. Check ALL local branches with numeric prefix
  // Note: git branch prefixes are: * (current), + (checked out in another worktree), space (normal)
  try {
    const localOutput = await execGit(["branch", "--list"], repoRoot);
    const localPattern = /^[\*\+]?\s*(\d+)-/gm;
    let match;
    const localNums: number[] = [];
    while ((match = localPattern.exec(localOutput)) !== null) {
      localNums.push(parseInt(match[1], 10));
    }
    numbers.push(...localNums);

    if (Deno.env.get("I3PM_DEBUG")) {
      console.error(`[DEBUG] Local branches: found ${localNums.length} nums, max=${Math.max(...localNums, 0)}`);
      // Show last 5 lines of output for debugging
      const lastLines = localOutput.trim().split("\n").slice(-5);
      console.error(`[DEBUG] Last 5 branches: ${lastLines.join(" | ")}`);
    }
  } catch {
    // No matching local branches
  }

  // 4. Check worktree branches (not visible in regular branch list)
  try {
    const worktreeOutput = await execGit(["worktree", "list", "--porcelain"], repoRoot);
    const worktreePattern = /^branch refs\/heads\/(\d+)-/gm;
    let match;
    while ((match = worktreePattern.exec(worktreeOutput)) !== null) {
      numbers.push(parseInt(match[1], 10));
    }
  } catch {
    // No worktrees or git worktree not supported
  }

  // 5. Check ALL specs directories with numeric prefix
  try {
    const specsDir = `${repoRoot}/specs`;
    for await (const entry of Deno.readDir(specsDir)) {
      if (entry.isDirectory) {
        const dirPattern = /^(\d+)-/;
        const match = entry.name.match(dirPattern);
        if (match) {
          numbers.push(parseInt(match[1], 10));
        }
      }
    }
  } catch {
    // Specs directory doesn't exist or no matching dirs
  }

  // Find highest number and return next
  const maxNumber = numbers.length > 0 ? Math.max(...numbers) : 0;

  // Debug output (remove after fixing)
  if (Deno.env.get("I3PM_DEBUG")) {
    console.error(`[DEBUG] Found ${numbers.length} numbers, max=${maxNumber}, next=${maxNumber + 1}`);
  }

  return maxNumber + 1;
}

/**
 * Generate a complete feature branch name from a description
 * Returns: { branchName: "078-user-auth", suffix: "user-auth", number: 78 }
 */
export async function generateFeatureBranchName(
  description: string,
  repoRoot: string
): Promise<{ branchName: string; suffix: string; number: number }> {
  const suffix = generateBranchSuffix(description);
  const number = await findNextFeatureNumber(suffix, repoRoot);
  const branchName = `${String(number).padStart(3, "0")}-${suffix}`;

  return { branchName, suffix, number };
}
