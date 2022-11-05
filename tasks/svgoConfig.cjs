module.exports = {
	plugins: [
		'cleanupAttrs',
		'removeDoctype',
		'removeXMLProcInst',
		'removeComments', // @note N'efface pas les commentaires avec un `!`, tel que ceux posé par Font Awesome. À supprimer manuellement par rechercher/remplacer.
		'removeDimensions',
		'removeMetadata',
		'removeUselessDefs',
		'removeEditorsNSData',
		'removeEmptyAttrs',
		'removeEmptyText',
		'removeEmptyContainers',
		'cleanupEnableBackground',
		'convertStyleToAttrs',
		'removeUselessStrokeAndFill',
		'removeDimensions',
		'cleanupIds',
		{
			name: 'removeViewBox',
			enabled: false
		},
		{
			name: 'prefixIds',
			params: {
				prefix: {
					toString() {
						this.counter = this.counter || 0

						return `svgo-viewbox-id-${this.counter++}`
					}
				}
			}
		}
	]
}
