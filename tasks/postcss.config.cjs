// @see https://www.freecodecamp.org/news/what-is-postcss/

module.exports = {
  map: { inline: false },
  plugins: [
    require('postcss-import'),
    require('postcss-advanced-variables'),
    require('postcss-calc'),
    /*
    require('postcss-preset-env')({
      stage: 4,
      features: {
        'nesting-rules': true
      }
    }),
    */
    process.env.NODE_ENV === 'production' ? require('postcss-minify') : ''
  ],
}
