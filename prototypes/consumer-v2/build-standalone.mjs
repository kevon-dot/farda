import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const directory = path.dirname(fileURLToPath(import.meta.url));
let html = readFileSync(path.join(directory, 'index.html'), 'utf8');
html = html.replace('<link rel="stylesheet" href="style.css">', '<style>' + readFileSync(path.join(directory, 'style.css'), 'utf8') + '</style>');
for (const script of ['model.js', 'app.js']) {
  html = html.replace('<script src="' + script + '"></script>', () => '<script>' + readFileSync(path.join(directory, script), 'utf8') + '</script>');
}
for (const [asset, mime] of [
  ['../../farda-app/assets/fonts/Outfit-Regular.ttf', 'font/ttf'],
  ['../../farda-app/assets/fonts/Outfit-SemiBold.ttf', 'font/ttf'],
  ['../../farda-app/assets/images/vial_bottle.png', 'image/png'],
  ['assets/farda-companion.png', 'image/png'],
]) {
  const encoded = readFileSync(path.resolve(directory, asset)).toString('base64');
  html = html.replaceAll(asset, 'data:' + mime + ';base64,' + encoded);
}
writeFileSync(path.join(directory, 'farda-navy-mock.html'), html);
console.log('Built farda-navy-mock.html — self-contained, synthetic data, no external services.');
