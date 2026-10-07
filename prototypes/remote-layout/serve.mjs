// PROTOTYPE — throwaway static server for issue #6.
// Serves this folder on 127.0.0.1:8484, which `tailscale serve` already proxies
// to https://<your-mac>.<your-tailnet>.ts.net/ — open that on the iPhone.
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const root = import.meta.dirname;
const types = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
};

http
  .createServer(async (req, res) => {
    const path = new URL(req.url, 'http://x').pathname;
    const file = join(root, normalize(path === '/' ? '/index.html' : path));
    try {
      const body = await readFile(file);
      res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream', 'cache-control': 'no-store' });
      res.end(body);
    } catch {
      res.writeHead(404).end('not found');
    }
  })
  .listen(8484, '127.0.0.1', () => {
    console.log('Remote layout prototype: http://127.0.0.1:8484');
    console.log('On the iPhone:            https://<your-mac>.<your-tailnet>.ts.net/');
  });
