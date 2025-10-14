import { execSync } from 'node:child_process';
import { ArgumentParser } from 'argparse';
import { setTimeout as sleep } from 'node:timers/promises';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
const DEFAULT_WORKFLOW_FILE = '.github/workflows/ci-orchestrated.yml';
function resolveRepo() {
    const fromEnv = process.env.GITHUB_REPOSITORY;
    if (fromEnv) {
        return fromEnv;
    }
    try {
        const remote = execSync('git config --get remote.origin.url', { encoding: 'utf8' }).trim();
        if (remote.endsWith('.git')) {
            const clean = remote.slice(0, -4);
            return clean.split(':').pop()?.split('/github.com/').pop() ?? clean;
        }
        return remote.split(':').pop() ?? remote;
    }
    catch (err) {
        throw new Error(`Unable to determine repository. Set GITHUB_REPOSITORY. (${err.message})`);
    }
}
async function fetchJson(url, token) {
    const headers = {
        Accept: 'application/vnd.github+json',
    };
    if (token) {
        headers.Authorization = `Bearer ${token}`;
    }
    const res = await fetch(url, { headers });
    const text = await res.text();
    if (!res.ok) {
        throw new Error(`GitHub request failed (${res.status} ${res.statusText}): ${text}`);
    }
    try {
        return JSON.parse(text);
    }
    catch (err) {
        throw new Error(`Failed to parse JSON from GitHub (${url}): ${err.message}\nResponse:\n${text}`);
    }
}
async function findLatestRun(repo, workflow, branch, token) {
    const url = `https://api.github.com/repos/${repo}/actions/workflows/${encodeURIComponent(workflow)}/runs?branch=${encodeURIComponent(branch)}&per_page=5`;
    const data = await fetchJson(url, token);
    return data.workflow_runs?.[0];
}
function formatJob(job) {
    const status = job.status ?? 'unknown';
    const conclusion = job.conclusion ?? '';
    const suffix = conclusion ? ` (${conclusion})` : '';
    return `- ${job.name}: ${status}${suffix}`;
}
async function watchRun(repo, runId, token, pollMs = 15000) {
    // eslint-disable-next-line no-console
    console.log(`Watching run ${runId} in ${repo}...`);
    let latestRun;
    let latestJobs = [];
    while (true) {
        try {
            const runUrl = `https://api.github.com/repos/${repo}/actions/runs/${runId}`;
            latestRun = await fetchJson(runUrl, token);
            const title = latestRun.display_title ?? `Run ${latestRun.id}`;
            const status = latestRun.status ?? 'unknown';
            const conclusion = latestRun.conclusion ?? '';
            const branch = latestRun.head_branch ?? '';
            const sha = latestRun.head_sha ?? '';
            // eslint-disable-next-line no-console
            console.log(`\n${title}`);
            // eslint-disable-next-line no-console
            console.log(`Status: ${status}  Conclusion: ${conclusion}`.trim());
            if (branch || sha) {
                // eslint-disable-next-line no-console
                console.log(`Ref: ${branch} ${sha}`.trim());
            }
            if (latestRun.html_url) {
                // eslint-disable-next-line no-console
                console.log(`URL: ${latestRun.html_url}`);
            }
            const jobsUrl = `https://api.github.com/repos/${repo}/actions/runs/${runId}/jobs?per_page=100`;
            const jobsResp = await fetchJson(jobsUrl, token);
            latestJobs = jobsResp.jobs ?? [];
            if (latestJobs.length) {
                // eslint-disable-next-line no-console
                console.log('Jobs:');
                for (const job of latestJobs) {
                    // eslint-disable-next-line no-console
                    console.log(formatJob(job));
                }
            }
            if (status === 'completed') {
                return {
                    schema: 'ci-watch/rest-v1',
                    repo,
                    runId,
                    branch: latestRun.head_branch ?? undefined,
                    headSha: latestRun.head_sha ?? undefined,
                    status: latestRun.status ?? undefined,
                    conclusion: latestRun.conclusion ?? undefined,
                    htmlUrl: latestRun.html_url ?? undefined,
                    displayTitle: latestRun.display_title ?? undefined,
                    polledAtUtc: new Date().toISOString(),
                    jobs: latestJobs.map((job) => ({
                        id: job.id,
                        name: job.name,
                        status: job.status,
                        conclusion: job.conclusion ?? undefined,
                        htmlUrl: job.html_url ?? undefined,
                    })),
                };
            }
        }
        catch (err) {
            // eslint-disable-next-line no-console
            console.error(`[watcher] ${(err.message).trim()}`);
        }
        await sleep(pollMs);
    }
}
async function main() {
    const parser = new ArgumentParser({
        description: 'Watch GitHub Actions run for ci-orchestrated.yml',
    });
    parser.add_argument('--run-id', { type: Number, help: 'Workflow run id to follow' });
    parser.add_argument('--branch', { help: 'Branch to locate the most recent run (if run id missing)' });
    parser.add_argument('--workflow', { default: DEFAULT_WORKFLOW_FILE, help: 'Workflow file name (default: ci-orchestrated)' });
    parser.add_argument('--poll-ms', { type: Number, default: 15000, help: 'Polling interval in milliseconds' });
    parser.add_argument('--out', { help: 'Optional path to write watcher summary JSON' });
    const args = parser.parse_args();
    const repo = resolveRepo();
    const token = process.env.GH_TOKEN ?? process.env.GITHUB_TOKEN ?? undefined;
    let runId = args.run_id;
    if (!runId) {
        if (!args.branch) {
            throw new Error('Provide --run-id or --branch');
        }
        const latest = await findLatestRun(repo, args.workflow, args.branch, token);
        if (!latest) {
            throw new Error(`No runs found for branch ${args.branch}`);
        }
        runId = latest.id;
    }
    const summary = await watchRun(repo, runId, token, args.poll_ms ?? 15000);
    if (args.out) {
        const outPath = resolve(process.cwd(), args.out);
        mkdirSync(dirname(outPath), { recursive: true });
        writeFileSync(outPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
    }
    if (summary.conclusion && summary.conclusion.toLowerCase() !== 'success') {
        process.exitCode = 1;
    }
}
main().catch((err) => {
    console.error(`[watcher] fatal: ${err.message}`);
    process.exitCode = 1;
});
