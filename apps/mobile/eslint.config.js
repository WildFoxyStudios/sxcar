module.exports = [
  ...require('eslint-config-expo/flat'),
  {
    ignores: [
      'dist',
      'node_modules',
      '.expo',
      'build',
      'web-build',
    ],
  },
];
