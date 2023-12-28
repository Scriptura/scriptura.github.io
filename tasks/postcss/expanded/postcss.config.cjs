// @see https://www.freecodecamp.org/news/what-is-postcss/

module.exports = {
  map: { inline: false },
  plugins: [
    require('postcss-import'),
    require('postcss-mixins'),
    require('postcss-for'),
    /*
    require('postcss-each')({
      plugins: {
        afterEach: [
          require('postcss-simple-vars')
        ],
        beforeEach: [
          require('postcss-simple-vars')
        ]
      }
    }),
    */
    require('postcss-simple-vars'),
    require('postcss-calc'),
    require('postcss-preset-env')({
      stage: 4,
      features: {
        'nesting-rules': true
      }
    }),
  ],
}
