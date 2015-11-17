fs          = require 'fs'
path        = require 'path'
_           = require 'lodash'
minimatch   = require 'minimatch'
Imagemin    = require 'imagemin'
pngquant    = require 'imagemin-pngquant'
jpegoptim   = require 'imagemin-jpegoptim'
RootsUtil   = require 'roots-util'
yaml        = require 'js-yaml'
gm          = require 'gm'

module.exports = (opts) ->
  opt = _.defaults opts,
    files: ['assets/img/**']
    manifest: false
    out: 'img'
    compress: true
    jpegoptim:
      progressive: true
      max: 80
    pngquant:
      quality: '65-80'
      speed: 4
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
          retina: true     # Include @2X images
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
            input = path.join(
              @roots.config.output
              @util.output_path(file_path).relative
            )

            # Build the filename to use for the new, resized file
            size_string = ""
            size_string += "-#{size.width}w" if size.width
            size_string += "-#{size.height}h" if size.height

            # Create an object containing options for resizing
            resize_opts =
              width: size.width
              height: size.height

            ext = "#{size_string}#{path.extname(file_path)}"
            resized = file_path.replace(path.extname(file_path), ext)
            output = path.join(
              @roots.config.output
              @util.output_path(resized).relative
            )

            # Trigger the resize asynchronously
            resize_image.call @, input, output, resize_opts

            if image_opt.retina
              resize_opts_2x =
                width: size.width * 2
                height: size.height * 2

              ext_2x = "#{size_string}-@2X#{path.extname(file_path)}"
              resized_2x = file_path.replace(path.extname(file_path), ext_2x)
              output_2x = path.join(
                @roots.config.output
                @util.output_path(resized_2x).relative
              )

              # Trigger the resize asynchronously
              resize_image.call @, input, output_2x, resize_opts_2x

            # Render a basic image tag for the fallback
            if size.media == 'fallback'
              return @picture.push "<img src='/#{resized}'>"

            # Add a source element for each of the provided sizes
            srcset = "/#{resized} 1x"
            srcset += ", /#{resized_2x} 2x" if image_opt.retina

            source = "<source srcset='#{srcset}'"
            source += " media='#{size.media}'" if size.media?
            source += ">"

            @picture.push source
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
        .use( pngquant(opt.pngquant) )
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