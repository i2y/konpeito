# extconf.rb for konpeito_json
require 'mkmf'

# yyjson source location
yyjson_dir = File.expand_path('../../../../vendor/yyjson', __dir__)

# Add yyjson to include path
$INCFLAGS << " -I#{yyjson_dir}"

# Add yyjson.c to sources
$srcs = ['json_native.c', File.join(yyjson_dir, 'yyjson.c')]
$VPATH << yyjson_dir

# Optimization flags
$CFLAGS << ' -O3'

create_makefile('konpeito_json')
