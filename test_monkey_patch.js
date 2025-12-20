const cp = require('child_process');
const originalSpawn = cp.spawn;

cp.spawn = function(command, args, options) {
  console.log('Intercepted spawn of:', command);
  const newOptions = { ...options };
  if (newOptions.env) {
    newOptions.env = { ...newOptions.env, INTERCEPTED: 'true' };
  } else {
    newOptions.env = { ...process.env, INTERCEPTED: 'true' };
  }
  return originalSpawn.call(this, command, args, newOptions);
};

const child = cp.spawn('node', ['-e', 'console.log("Child INTERCEPTED =", process.env.INTERCEPTED)'], {
  env: { SOME_VAR: 'value' } // Claude Code isolation simulation
});

child.stdout.on('data', d => console.log(d.toString().trim()));
