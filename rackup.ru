require 'ruhoh'

use Rack::Static, urls: {
  "/assets/media/bgs/body.png" => "body.png",
  "/assets/media/bgs/navbar.png" => "navbar.png"
}, root: "my_hooligan/media/bgs"

run Ruhoh::Program.preview

# To preview your blog in "production" mode:
# run Ruhoh::Program.preview(:env => 'production')
