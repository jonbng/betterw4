import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, rmSync, statSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";

const root = dirname(fileURLToPath(import.meta.url));
const output = join(root, "output");
const assets = join(root, "assets");
const required = [
  "timetable-en-light.png",
  "students-en-light.png",
  "classes-en-light.png",
  "houses-en-light.png",
  "assessments-en-light.png",
  "absence-en-dark.png",
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

const names = ["01-w4-now-on-mobile", "02-students", "03-classes", "04-houses", "05-assessments", "06-absence"];
for (const [index, name] of names.entries()) {
  const target = join(output, `${name}.png`);
  execFileSync("magick", [panorama, "-crop", `1080x1920+${index * 1080}+0`, "+repage", "-alpha", "off", "-colorspace", "sRGB", target]);
  const size = statSync(target).size;
  if (size > 8 * 1024 * 1024) throw new Error(`${name}.png exceeds 8 MB`);
}

const featureGraphic = join(output, "feature-graphic.png");
const featurePage = `${pathToFileURL(join(root, "feature-graphic.html")).href}`;
execFileSync("google-chrome", [
  "--headless=new",
  "--no-sandbox",
  "--disable-gpu",
  "--hide-scrollbars",
  "--force-device-scale-factor=1",
  "--window-size=1024,500",
  "--virtual-time-budget=3000",
  `--screenshot=${featureGraphic}`,
  featurePage,
], { stdio: "inherit" });
execFileSync("magick", [featureGraphic, "-alpha", "off", "-colorspace", "sRGB", featureGraphic]);
const featureSize = execFileSync("magick", ["identify", "-format", "%w %h", featureGraphic], { encoding: "utf8" }).trim();
if (featureSize !== "1024 500") throw new Error(`Feature graphic must be 1024x500, got ${featureSize}`);

console.log(`Created panorama, ${names.length} Play Store screenshots, and feature-graphic.png in ${output}`);
