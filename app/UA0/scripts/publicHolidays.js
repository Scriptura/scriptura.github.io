const addDays = (date, days) => new Date(date.getTime() + days * 24 * 60 * 60 * 1000)

const easter = function (year) {
  const a = year % 19
  const century = Math.floor(year / 100)
  const yearsAfterCentury = year % 100
  const d = (19 * a + century - Math.floor(century / 4) - Math.floor((Math.floor(century - (century + 8) / 25) + 1) / 3) + 15) % 30
  const e = (32 + 2 * (century % 4) + 2 * Math.floor(yearsAfterCentury / 4) - d - (yearsAfterCentury % 4)) % 7
  const f = d + e - 7 * Math.floor((a + 11 * d + 22 * e) / 451) + 114
  const month = Math.floor(f / 31)
  const day = (f % 31) + 1

  return new Date(year, month - 1, day)
}

const holidays = year => ({
  Armistice: new Date(year, 10, 11),
  Ascension: addDays(easter(year), 39),
  Assumption: new Date(year, 7, 15),
  BastilleDay: new Date(year, 6, 14),
  LabourDay: new Date(year, 4, 1),
  NewYearSDay: new Date(year, 0, 1),
  PentecostMonday: addDays(easter(year), 50),
  EasterMonday: addDays(easter(year), 1),
  Christmas: new Date(year, 11, 25),
  AllSaintsDay: new Date(year, 10, 1),
  VictoryDay: new Date(year, 4, 8),
})

const alsaceHolidays = year => ({
  SaintStephenSDay: new Date(year, 11, 26),
  GoodFriday: addDays(easter(year), -2),
})

/**
 * Get French public holidays by year and region.
 *
 * @param {number} year the year you're interested in
 * @param {Object} [options] the region you're interested in ("mainland" by default)
 * @param {string} [options.region] the region (either "mainland" or "alsace-moselle")
 * @returns {Object} the list of holidays for the given year and region
 */
function publicHolidays(year, options = { region: 'mainland' }) {
  if (options.region === 'alsace-moselle') {
    return { ...holidays(year), ...alsaceHolidays(year) }
  } else {
    return holidays(year)
  }
}

//export { publicHolidays };
