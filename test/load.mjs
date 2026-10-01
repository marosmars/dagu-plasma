// Loads a QML-style JS library (".pragma library", no exports) into Node.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export function loadQmlJs(relPath, names) {
    const file = fileURLToPath(new URL(`../package/contents/code/${relPath}`, import.meta.url));
    const src = readFileSync(file, 'utf8').replace(/^\.pragma library\s*$/m, '');
    return new Function(`${src}\nreturn { ${names.join(', ')} };`)();
}
