const { Client } = require('pg');
const fs = require('fs');

const client = new Client({
  host: '2a05:d018:135e:1640:8231:baf3:4d4f:ccbb',
  port: 5432,
  database: 'postgres',
  user: 'postgres',
  password: process.env.PGPASSWORD || 'rupkkZOZGijJcKkC',
  ssl: { rejectUnauthorized: false },
  connectionTimeoutMillis: 30000,
});

async function dumpDatabase() {
  console.log('Connecting to Supabase database...');
  
  try {
    await client.connect();
    console.log('Connected!');

    // Get all tables
    const tablesResult = await client.query(`
      SELECT table_schema, table_name 
      FROM information_schema.tables 
      WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
      AND table_type = 'BASE TABLE'
      ORDER BY table_schema, table_name
    `);

    let dump = '-- Supabase Database Dump\n';
    dump += `-- Generated: ${new Date().toISOString()}\n\n`;
    dump += 'BEGIN;\n\n';

    // Dump schemas and tables
    for (const row of tablesResult.rows) {
      const schema = row.table_schema;
      const table = row.table_name;
      
      // Get CREATE TABLE statement
      const createResult = await client.query(`
        SELECT pg_get_catalog_writemask('${table}'::regclass)
      `).catch(() => null);
      
      // Get table data
      const dataResult = await client.query(`SELECT * FROM "${schema}"."${table}"`);
      
      if (dataResult.rows.length > 0) {
        console.log(`Dumping ${schema}.${table} (${dataResult.rows.length} rows)`);
        dump += `-- Table: ${schema}.${table}\n`;
        dump += `COPY "${schema}"."${table}" FROM stdin;\n`;
        
        const columns = dataResult.fields.map(f => f.name).join('\t');
        dump += columns + '\n';
        
        for (const row of dataResult.rows) {
          const values = dataResult.fields.map(f => {
            const val = row[f.name];
            if (val === null) return '\\N';
            if (val instanceof Buffer) return '\\x' + val.toString('hex');
            if (typeof val === 'object') return JSON.stringify(val).replace(/\\/g, '\\\\');
            return String(val).replace(/\t/g, '\\t').replace(/\n/g, '\\n');
          });
          dump += values.join('\t') + '\n';
        }
        dump += '\\.\n\n';
      }
    }

    dump += 'COMMIT;\n';

    fs.writeFileSync('supabase_backup_20260615.sql', dump);
    console.log('Backup saved to supabase_backup_20260615.sql');
    console.log(`File size: ${(dump.length / 1024 / 1024).toFixed(2)} MB`);

  } catch (err) {
    console.error('Error:', err.message);
  } finally {
    await client.end();
  }
}

dumpDatabase();
