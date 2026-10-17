if (process.env.NODE_ENV && process.env.NODE_ENV !== 'production') {
  console.error('Refusing production start with NODE_ENV other than production.');
  process.exitCode = 1;
} else {
  process.env.NODE_ENV = 'production';
  const { run } = require('../Server');
  void run();
}
