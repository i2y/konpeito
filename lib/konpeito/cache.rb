# frozen_string_literal: true

module Konpeito
  module Cache
    autoload :CacheManager, "konpeito/cache/cache_manager"
    autoload :DependencyGraph, "konpeito/cache/dependency_graph"
    autoload :RunCache, "konpeito/cache/run_cache"
  end
end
