fs          = require 'fs'
path        = require 'path'
_           = require 'lodash'
minimatch   = require 'minimatch'
Imagemin    = require 'imagemin'
RootsUtil   = require 'roots-util'
yaml        = require 'js-yaml'
gm          = require 'gm'

module.exports = (opts) ->
  opt = _.defaults opts,
    files: ['assets/img/**']
    manifest: false
    out: 'img'
    compress: true
    jpegtran:
      progressive: true
    optipng:
      optimizationLevel: 3
    gifsicle:
      interlaced: true
    svgo: {}

  class ImagePipeline

    ###*
     * Creates an image() function in template locals, which handles compression
     * of images using imagemin, and resizing and rendering multiple images in a
     * html <picture> element
     *
     * @method  constructor
     *
     * @param   {Object}    roots  Roots context
     *
     * @return  {Function}         image() function for use in views
    ###

    constructor: (@roots) ->
      @category = 'imagePipeline'
      @file_map = {}
      @util = new RootsUtil(@roots)
      @helpers = new RootsUtil.Helpers(base: path.join(__dirname, 'public'))

      # Check for a manifest file
      if opt.manifest
        @roots.config.ignores.push(opts.manifest)
        @manifest = load_manifest_file.call(@, opts.manifest)

      # Use the manifest, or the passed-in files array
      @files = @manifest or opts.files

      # Initialise locals if not done already
      @roots.config.locals ?= {}

      ###*
       * Output an image element, or a picture element with matching
       * sources if image_opts.sizes is provided
       *
       * @method  image
       *
       * @param   {String}  filename    File path of the image to be rendered
       * @param   {Object}  image_opts  Image rendering options
       *
       * @return  {String}              HTML for displaying the image
      ###

      @roots.config.locals.image = (filename = '', image_opts = {}) =>
        image_opt = _.defaults image_opts,
          prefix: opt.out  # File path prefix
          sizes: false     # Optional array containing source sizes

        # Get the file path for rendering in browser
        file_path = path.join image_opt.prefix, filename

        # If no sizes are specified, just use the default
        if !image_opt.sizes
          "<img src='/#{file_path}'>"

        # Loop through the sizes array
        @picture = []
        for size in image_opt.sizes
          ((file_path, size) =>
            # Create an object containing options for resizing
            resize_opts =
              media: size.media
              width: size.width
              height: size.height

            # Build the filename to use for the new, resized file
            ext = ""
            ext += "-#{size.width}w" if size.width
            ext += "-#{size.height}h" if size.height
            ext += "#{path.extname(file_path)}"
            resized_file_path = file_path.replace(path.extname(file_path), ext)

            # Trigger the resize asynchronously
            resize_image.call(
              @
              path.join(
                @roots.config.output
                @util.output_path(file_path).relative
              )
              path.join(
                @roots.config.output
                @util.output_path(resized_file_path).relative
              )
              resize_opts
            )

            # Render a basic image tag for the fallback
            if resize_opts.media == 'fallback'
              return @picture.push "<img src='/#{resized_file_path}'>"

            # Add a source element for each of the provided sizes
            @picture.push "<source srcset='/#{resized_file_path}'
                                   media='#{resize_opts.media}'>"
          )(file_path, size)

        # Output the picture element in our template
        "<picture>#{@picture.join("\n")}</picture>"

    ###*
     * Minimatch runs against each path, quick and easy.
    ###

    fs: ->
      extract: true
      ordered: true
      detect: (f) => _.any(@files, minimatch.bind(@, f.relative))

    ###*
     * Load the manifest file for this plugin
    ###

    load_manifest_file = (f) ->
      res = yaml.safeLoad(fs.readFileSync(path.join(@roots.root, f), 'utf8'))
      res.map((m) -> path.join(path.dirname(f), m))

    ###*
     * Loop through input file matchers and compress images before outputting
    ###

    category_hooks: ->
      after: (ctx) =>
        if not opt.out then return

        if opt.compress
          for matcher in @files
            compress_images @files, path.join(@roots.config.output, opt.out)

    ###*
     * Pass an image through Imagemin plugins to increase compression
     *
     * TODO: Add ability to specify options for these
     *
     * @method  compress_images
     *
     * @param {String} files  A minimatch string matching input files
     * @param {String} out    Output folder to store images in
    ###

    compress_images = (files, out) ->
      new Imagemin()
        .src(files)
        .dest(out)
        .use( Imagemin.gifsicle(opt.gifsicle) )
        .use( Imagemin.optipng(opt.optipng) )
        .use( Imagemin.jpegtran(opt.jpegtran) )
        .use( Imagemin.svgo(opt.svgo) )
        .run((err, compressed) ->
          if err
            console.log err
        )

    ###*
     * Resize the provided image, and store at the path specified in 'out'
     *
     * @method  resize_image
     *
     * @param {String}    filename  The input filename
     * @param {String}    out       The output filename
     * @param {Object}    opts      Resize options
     * @param {Function}  cb        A callback function
    ###

    resize_image = (filename, out, opts, cb) ->
      resize_opt = _.defaults opts,
        width: false
        height: false
        prefix: ''

      gm(filename)
        .resize(resize_opt.width, resize_opt.height)
        .noProfile()
        .write(out, (err) ->
          if err
            return console.log err
        )