fs          = require 'fs'
path        = require 'path'
_           = require 'lodash'
minimatch   = require 'minimatch'
Imagemin    = require 'imagemin'
pngquant    = require 'imagemin-pngquant'
jpegoptim   = require 'imagemin-jpegoptim'
webp        = require 'imagemin-webp'
RootsUtil   = require 'roots-util'
yaml        = require 'js-yaml'
gm          = require 'gm'

module.exports = (opts) ->
  opt = _.defaultsDeep opts,
    files: ['assets/img/**']
    manifest: false
    out: 'img'
    compress: true
    resize: true
    opts:
      jpegoptim:
        progressive: true
        max: 70
      pngquant:
        quality: '50-70'
        speed: 1
      gifsicle:
        interlaced: true
      svgo: {}
      webp:
        quality: 70
        alphaQuality: 50
        lossless: false
    output_webp: false

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
      @category = 'images'
      @file_map = {}
      @file_queue = {}
      @util = new RootsUtil(@roots)
      @helpers = new RootsUtil.Helpers(base: @roots.root)

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
        if !opt.resize || !image_opt.sizes
          return "<img src='/#{file_path}'>"

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
                width: (size.width * 2 if size.width?)
                height: (size.height * 2 if size.height?)

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
      category: 'images'
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
      after: () =>
        if not opt.out then return

        if !Array.isArray @files
          @files = [@files]

        if opt.compress
          for matcher in @files
            compress_images matcher, path.join(@roots.config.output, opt.out)

    ###*
     * Pass an image through Imagemin plugins to increase compression
     *
     * @method  compress_images
     *
     * @param {String|Buffer} files  A minimatch string matching input files,
     *                               or a file buffer
     * @param {String}        out    Output folder to store images in
    ###

    compress_images = (files, out) ->
      new Imagemin()
        .src files
        .dest out
        .use jpegoptim(opt.opts.jpegoptim)
        .use pngquant(opt.opts.pngquant)
        .use Imagemin.gifsicle(opt.opts.gifsicle)
        .use Imagemin.svgo(opt.opts.svgo)
        .run (err) ->
          if err
            return console.log 'Image compression error: ', files, ' - ', err

          if opt.output_webp
            convert_to_webp.call @, files, out

    ###*
     * Pass an image through Imagemin to convert to webp
     *
     * @method  convert_to_webp
     *
     * @param {String|Buffer} files  A minimatch string matching input files,
     *                               or a file buffer
     * @param {String}        out    Output folder to store images in
    ###

    convert_to_webp = (files, out) ->
      new Imagemin()
        .src files
        .dest out
        .use webp(opt.opts.webp)
        .run (err) ->
          if err
            return console.log 'WebP conversion error: ', files, ' - ', err

    ###*
     * Resize the provided image, and store at the path specified in 'out'
     *
     * @method  resize_image
     *
     * @param {String|Buffer}  filename  The input file
     * @param {String}         out       The output file
     * @param {Object}         opts      Resize options
     * @param {Function}       cb        A callback function
    ###

    resize_image = (filename, out, opts) ->
      resize_opt = _.defaults opts,
        width: false
        height: false
        prefix: ''

      process = =>
        if !@helpers.file.exists(filename)
          return setTimeout process, 1000

        gm(filename)
          .resize resize_opt.width, resize_opt.height
          .noProfile()
          .write out, (err) ->
            if err
              return console.log 'Resize error: ', filename, out, ' - ', err

            if opt.compress
              compress_images.call @, out, path.dirname(out)

      setTimeout process, 1000
