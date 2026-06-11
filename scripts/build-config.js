const fs = require('fs');
const url = process.env.SUPABASE_URL || 'https://TU-PROYECTO.supabase.co';
const key = process.env.SUPABASE_ANON_KEY || 'tu-anon-key-aqui';
fs.writeFileSync(
  'config.js',
  `window.ERIOR_CONFIG = {\n  SUPABASE_URL: '${url}',\n  SUPABASE_ANON_KEY: '${key}',\n};\n`
);
console.log('config.js generated for deploy');
