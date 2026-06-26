const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

// App autocontenido: no resolver hacia el root del monorepo en F0.4.
config.watchFolders = [__dirname];

module.exports = config;
