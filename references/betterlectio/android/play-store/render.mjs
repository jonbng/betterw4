import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, rmSync, statSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";

const root = dirname(fileURLToPath(import.meta.url));
const output = join(root, "output");
const assets = join(root, "assets");
const required = [
  "schedule-da-light.png",
  "messages-da-light.png",
  "homework-da-light.png",
  "assignments-da-light.png",
  "student-da-light.png",
  "absence-da-dark.png",
];

for (const file of required) {
  const path = join(assets, file);
  if (!existsSync(path)) throw new Error(`Missing screenshot: ${path}`);
  const dimensions = execFileSync("magick", ["identify", "-format", "%w %h", path], { encoding: "utf8" }).trim();
  if (dimensions !== "1280 2856") throw new Error(`${file} must be 1280x2856, got ${dimensions}`);
}

mkdirSync(output, { recursive: true });
for (const file of readdirSync(output)) rmSync(join(output, file));

const panorama = join(output, "panorama.png");
const page = `${pathToFileURL(join(root, "index.html")).href}?export=1`;
execFileSync("google-chrome", [
  "--headless=new",
  "--no-sandbox",
  "--disable-gpu",
  "--hide-scrollbars",
  "--force-device-scale-factor=1",
  "--window-size=6480,1920",
  "--virtual-time-budget=3000",
  `--screenshot=${panorama}`,
  page,
], { stdio: "inherit" });

const dimensions = execFileSync("magick", ["identify", "-format", "%w %h", panorama], { encoding: "utf8" }).trim();
if (dimensions !== "6480 1920") throw new Error(`Panorama must be 6480x1920, got ${dimensions}`);

const names = ["01-lectio-bare-bedre", "02-beskeder", "03-lektier", "04-opgaver", "05-klassen", "06-fravaer"];
for (const [index, name] of names.entries()) {
  const target = join(output, `${name}.png`);
  execFileSync("magick", [panorama, "-crop", `1080x1920+${index * 1080}+0`, "+repage", "-alpha", "off", "-colorspace", "sRGB", target]);
  const size = statSync(target).size;
  if (size > 8 * 1024 * 1024) throw new Error(`${name}.png exceeds 8 MB`);
}

console.log(`Created panorama and ${names.length} Play Store screenshots in ${output}`);
