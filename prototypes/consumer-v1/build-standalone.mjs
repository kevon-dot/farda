import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const directory = path.dirname(fileURLToPath(import.meta.url));
let html = readFileSync(path.join(directory, 'index.html'), 'utf8');
for (const [asset, type] of [
  ['../../farda-app/assets/fonts/Outfit-Regular.ttf', 'font/ttf'],
  ['../../farda-app/assets/fonts/Outfit-SemiBold.ttf', 'font/ttf'],
  ['../../farda-app/assets/images/vial_bottle.png', 'image/png'],
]) {
  const data = readFileSync(path.resolve(directory, asset)).toString('base64');
  html = html.replaceAll(asset, `data:${type};base64,${data}`);
}
writeFileSync(path.join(directory, 'farda-consumer-mock.html'), html);
console.log('Built standalone consumer mock with embedded fonts and existing vial asset.');
