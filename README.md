Roots Image Pipeline
=================

[![Join the chat at https://gitter.im/molovo/roots-image-pipeline](https://badges.gitter.im/molovo/roots-image-pipeline.svg)](https://gitter.im/molovo/roots-image-pipeline?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

Roots image pipeline is an asset pipeline for images which optionally compresses using imagemin and/or generates multiple sizes for use in HTML `<picture>` elements.

> **Note:** This project is in early development, and versioning is a little different. [Read this](http://markup.im/#q4_cRZ1Q) for more details.

### Installation

- make sure you are in your roots project directory
- `npm install roots-image-pipeline --save`
- modify your `app.coffee` file to include the extension, for example:

  ```coffee
  image_pipeline = require('roots-image-pipeline')

  module.exports =
    extensions: [image_pipeline(files: "assets/img/**", out: 'img', compress: true)]
  ```

### Usage in templates

The function `image()` is exposed to your roots views, allowing you to output images quickly and easily. At it's simplest, simply pass `image()` a path to an image relative to the output directory specified in the function.

```jade
//- views/simple-example.jade
div.image-wrapper
  != image('example/image.png')

  //- <img src="/img/example/image.png">
```

`image()` takes a number of options which determine how the image is resized and displayed.

##### Sizes

Passing an array of sizes, containing a media query as well as width and/or height will generate the different sized images at compile time, and render the correct path for each source in your template.

```jade
//- views/picture-example.jade
div.picture-wrapper
  != image('example/image.png', {sizes: [{media: '(min-width: 40em)', width: 1024}, {width: 700}, {media: 'fallback', width: 1024}]})

  //- <picture>
  //-   <source srcset="/img/example/image-1024w.png" media="(min-width: 40em)">
  //-   <source srcset="/img/example/image-700w.png">
  //-   <img src="/img/example/image-1024w.png">
  //- </picture>
```

##### @2X Images

Passing `retina: true` in the options object will also generate and add the sources for @2x assets.

```jade
//- views/picture-example.jade
div.picture-wrapper
  != image('example/image.png', {sizes: [{media: '(min-width: 40em)', width: 1024}, {width: 700}, {media: 'fallback', width: 1024}], retina: true})

  //- <picture>
  //-   <source srcset="/img/example/image-1024w.png 1x, /img/example/image-1024w-@2X.png 2x" media="(min-width: 40em)">
  //-   <source srcset="/img/example/image-700w.png 1x, /img/example/image-700w-@2X.png 2x">
  //-   <img src="/img/example/image-1024w.png">
  //- </picture>
```

### Options

##### files
String or array of strings ([minimatch](https://github.com/isaacs/minimatch) supported) pointing to one or more file paths to be built. Default is `assets/img/**`

##### manifest
A path, relative to the roots project's root, to a _manifest file_ (explained above), which contains a list of strings ([minimatch](https://github.com/isaacs/minimatch) supported) pointing to one more more file paths to be built.

##### out
If provided, all image files will be output to this directory in your project's output. Default is `img`

##### compress
Compresses images. Default is `true`.

##### opts
Options to be passed into imagemin plugins. Only does anything useful when compress is true.

```coffeescript
# Defaults
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
```

##### output_webp
When true, after an image is passed through the compressor, a new .webp image is created in the output directory, alongside the matching jpg/png. Default is `false`.

> Caveat: Converting some large png images with high levels of transparency can occasionally leave you with a webp image far larger than the original png. Use with caution.

To conditionally serve webp images to those browsers who can display them, add the following to your nginx configuration:
```nginx
http {
  ...

  map $http_accept $webp_suffix {
    default "";
    "~*webp" ".webp";
  }

  ...
}

server {
  ...

  # Load webp images instead of jpg/png if browser headers indicate support and files exist
  location ~* ^(?P<basename>.+)\.(jpg|jpeg|png)$ {
    try_files $basename$webp_suffix $uri =404;
  }

  ...
}
```

Any option accepted by the various imagemin plugins can be passed through here.

### License & Contributing

- Details on the license [can be found here](LICENSE.md)
- Details on running tests and contributing [can be found here](CONTRIBUTING.md)
