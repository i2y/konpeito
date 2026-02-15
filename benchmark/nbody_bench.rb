# frozen_string_literal: true

# N-Body Benchmark from the Computer Language Benchmarks Game
# https://benchmarksgame-team.pages.debian.net/benchmarksgame/
#
# Simulates the orbits of Jovian planets using a symplectic integrator.
# Tests: NativeClass (Body), NativeArray[Body], @cfunc sqrt, unboxed Float arithmetic

require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

# ============================================================================
# Native code (compiled by Konpeito)
# ============================================================================
NATIVE_SOURCE = <<~'RUBY'
  class Body
    def x; end
    def x=(v); end
    def y; end
    def y=(v); end
    def z; end
    def z=(v); end
    def vx; end
    def vx=(v); end
    def vy; end
    def vy=(v); end
    def vz; end
    def vz=(v); end
    def mass; end
    def mass=(v); end
  end

  module MathLib
    def self.sqrt(x)
    end
  end

  def nbody_run(n)
    solar_mass = 39.47841760435743
    days_per_year = 365.24
    dt = 0.01

    bodies = NativeArray.new(5)

    # Sun (index 0)
    bodies[0].x = 0.0
    bodies[0].y = 0.0
    bodies[0].z = 0.0
    bodies[0].vx = 0.0
    bodies[0].vy = 0.0
    bodies[0].vz = 0.0
    bodies[0].mass = solar_mass

    # Jupiter (index 1)
    bodies[1].x = 4.84143144246472090
    bodies[1].y = -1.16032004402742839
    bodies[1].z = -0.103622044471123109
    bodies[1].vx = 0.00166007664274403694 * days_per_year
    bodies[1].vy = 0.00769901118419740425 * days_per_year
    bodies[1].vz = -0.0000690460016972063023 * days_per_year
    bodies[1].mass = 0.000954791938424326609 * solar_mass

    # Saturn (index 2)
    bodies[2].x = 8.34336671824457987
    bodies[2].y = 4.12479856412430479
    bodies[2].z = -0.403523417114321381
    bodies[2].vx = -0.00276742510726862411 * days_per_year
    bodies[2].vy = 0.00499852801234917238 * days_per_year
    bodies[2].vz = 0.0000230417297573763929 * days_per_year
    bodies[2].mass = 0.000285885980666130812 * solar_mass

    # Uranus (index 3)
    bodies[3].x = 12.8943695621391310
    bodies[3].y = -15.1111514016986312
    bodies[3].z = -0.223307578892655734
    bodies[3].vx = 0.00296460137564761618 * days_per_year
    bodies[3].vy = 0.00237847173959480950 * days_per_year
    bodies[3].vz = -0.0000296589568540237556 * days_per_year
    bodies[3].mass = 0.0000436624404335156298 * solar_mass

    # Neptune (index 4)
    bodies[4].x = 15.3796971148509165
    bodies[4].y = -25.9193146099879641
    bodies[4].z = 0.179258772950371181
    bodies[4].vx = 0.00268067772490389322 * days_per_year
    bodies[4].vy = 0.00162824170038242295 * days_per_year
    bodies[4].vz = -0.0000951592254519715870 * days_per_year
    bodies[4].mass = 0.0000515138902046611451 * solar_mass

    # Offset momentum (adjust Sun's velocity so total momentum = 0)
    px = 0.0
    py = 0.0
    pz = 0.0
    i = 0
    while i < 5
      px = px + bodies[i].vx * bodies[i].mass
      py = py + bodies[i].vy * bodies[i].mass
      pz = pz + bodies[i].vz * bodies[i].mass
      i = i + 1
    end
    bodies[0].vx = 0.0 - px / solar_mass
    bodies[0].vy = 0.0 - py / solar_mass
    bodies[0].vz = 0.0 - pz / solar_mass

    # Advance n steps
    step = 0
    while step < n
      # Force calculation (all pairs)
      i = 0
      while i < 5
        j = i + 1
        while j < 5
          dx = bodies[i].x - bodies[j].x
          dy = bodies[i].y - bodies[j].y
          dz = bodies[i].z - bodies[j].z
          dsq = dx * dx + dy * dy + dz * dz
          dist = MathLib.sqrt(dsq)
          mag = dt / (dsq * dist)
          bjm = bodies[j].mass * mag
          bim = bodies[i].mass * mag

          bodies[i].vx = bodies[i].vx - dx * bjm
          bodies[i].vy = bodies[i].vy - dy * bjm
          bodies[i].vz = bodies[i].vz - dz * bjm
          bodies[j].vx = bodies[j].vx + dx * bim
          bodies[j].vy = bodies[j].vy + dy * bim
          bodies[j].vz = bodies[j].vz + dz * bim

          j = j + 1
        end
        i = i + 1
      end

      # Position update
      i = 0
      while i < 5
        bodies[i].x = bodies[i].x + dt * bodies[i].vx
        bodies[i].y = bodies[i].y + dt * bodies[i].vy
        bodies[i].z = bodies[i].z + dt * bodies[i].vz
        i = i + 1
      end

      step = step + 1
    end

    # Compute energy
    e = 0.0
    i = 0
    while i < 5
      vx = bodies[i].vx
      vy = bodies[i].vy
      vz = bodies[i].vz
      e = e + 0.5 * bodies[i].mass * (vx * vx + vy * vy + vz * vz)
      j = i + 1
      while j < 5
        dx = bodies[i].x - bodies[j].x
        dy = bodies[i].y - bodies[j].y
        dz = bodies[i].z - bodies[j].z
        dist = MathLib.sqrt(dx * dx + dy * dy + dz * dz)
        e = e - (bodies[i].mass * bodies[j].mass) / dist
        j = j + 1
      end
      i = i + 1
    end

    e
  end
RUBY

NATIVE_RBS = <<~'RBS'
  class Body
    @x: Float
    @y: Float
    @z: Float
    @vx: Float
    @vy: Float
    @vz: Float
    @mass: Float

    def self.new: () -> Body
    def x: () -> Float
    def x=: (Float) -> Float
    def y: () -> Float
    def y=: (Float) -> Float
    def z: () -> Float
    def z=: (Float) -> Float
    def vx: () -> Float
    def vx=: (Float) -> Float
    def vy: () -> Float
    def vy=: (Float) -> Float
    def vz: () -> Float
    def vz=: (Float) -> Float
    def mass: () -> Float
    def mass=: (Float) -> Float
  end

  %a{ffi: "libm"}
  module MathLib
    %a{cfunc}
    def self.sqrt: (Float) -> Float
  end

  module TopLevel
    def nbody_run: (Integer n) -> Float
  end
RBS

# ============================================================================
# Pure Ruby equivalent (standard benchmarksgame implementation)
# ============================================================================
module PureRuby
  SOLAR_MASS = 4.0 * Math::PI * Math::PI
  DAYS_PER_YEAR = 365.24

  class Body
    attr_accessor :x, :y, :z, :vx, :vy, :vz, :mass

    def initialize(x, y, z, vx, vy, vz, mass)
      @x = x; @y = y; @z = z
      @vx = vx; @vy = vy; @vz = vz
      @mass = mass
    end
  end

  def self.create_bodies
    [
      Body.new(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS),
      Body.new(
        4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
        1.66007664274403694e-03 * DAYS_PER_YEAR, 7.69901118419740425e-03 * DAYS_PER_YEAR,
        -6.90460016972063023e-05 * DAYS_PER_YEAR, 9.54791938424326609e-04 * SOLAR_MASS
      ),
      Body.new(
        8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
        -2.76742510726862411e-03 * DAYS_PER_YEAR, 4.99852801234917238e-03 * DAYS_PER_YEAR,
        2.30417297573763929e-05 * DAYS_PER_YEAR, 2.85885980666130812e-04 * SOLAR_MASS
      ),
      Body.new(
        1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
        2.96460137564761618e-03 * DAYS_PER_YEAR, 2.37847173959480950e-03 * DAYS_PER_YEAR,
        -2.96589568540237556e-05 * DAYS_PER_YEAR, 4.36624404335156298e-05 * SOLAR_MASS
      ),
      Body.new(
        1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
        2.68067772490389322e-03 * DAYS_PER_YEAR, 1.62824170038242295e-03 * DAYS_PER_YEAR,
        -9.51592254519715870e-05 * DAYS_PER_YEAR, 5.15138902046611451e-05 * SOLAR_MASS
      ),
    ]
  end

  def self.offset_momentum(bodies)
    px = py = pz = 0.0
    bodies.each do |b|
      px += b.vx * b.mass
      py += b.vy * b.mass
      pz += b.vz * b.mass
    end
    bodies[0].vx = -px / SOLAR_MASS
    bodies[0].vy = -py / SOLAR_MASS
    bodies[0].vz = -pz / SOLAR_MASS
  end

  def self.advance(bodies, dt)
    nbodies = bodies.size
    i = 0
    while i < nbodies
      bi = bodies[i]
      j = i + 1
      while j < nbodies
        bj = bodies[j]
        dx = bi.x - bj.x
        dy = bi.y - bj.y
        dz = bi.z - bj.z
        dsq = dx * dx + dy * dy + dz * dz
        dist = Math.sqrt(dsq)
        mag = dt / (dsq * dist)

        bi.vx -= dx * bj.mass * mag
        bi.vy -= dy * bj.mass * mag
        bi.vz -= dz * bj.mass * mag
        bj.vx += dx * bi.mass * mag
        bj.vy += dy * bi.mass * mag
        bj.vz += dz * bi.mass * mag

        j += 1
      end
      i += 1
    end

    bodies.each do |b|
      b.x += dt * b.vx
      b.y += dt * b.vy
      b.z += dt * b.vz
    end
  end

  def self.energy(bodies)
    e = 0.0
    nbodies = bodies.size
    i = 0
    while i < nbodies
      bi = bodies[i]
      e += 0.5 * bi.mass * (bi.vx * bi.vx + bi.vy * bi.vy + bi.vz * bi.vz)
      j = i + 1
      while j < nbodies
        bj = bodies[j]
        dx = bi.x - bj.x
        dy = bi.y - bj.y
        dz = bi.z - bj.z
        dist = Math.sqrt(dx * dx + dy * dy + dz * dz)
        e -= (bi.mass * bj.mass) / dist
        j += 1
      end
      i += 1
    end
    e
  end

  def self.run(n)
    bodies = create_bodies
    offset_momentum(bodies)
    step = 0
    while step < n
      advance(bodies, 0.01)
      step += 1
    end
    energy(bodies)
  end
end

# ============================================================================
# Compilation
# ============================================================================
def compile_native
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  timestamp = Time.now.to_i
  source_path = File.join(tmp_dir, "nbody_#{timestamp}.rb")
  rbs_path = File.join(tmp_dir, "nbody_#{timestamp}.rbs")
  output_path = File.join(tmp_dir, "nbody_#{timestamp}.bundle")

  File.write(source_path, NATIVE_SOURCE)
  File.write(rbs_path, NATIVE_RBS)

  Konpeito::Compiler.new(
    source_file: source_path,
    output_file: output_path,
    format: :cruby_ext,
    rbs_paths: [rbs_path],
    optimize: true
  ).compile

  output_path
ensure
  File.unlink(source_path) rescue nil
  File.unlink(rbs_path) rescue nil
end

def measure_time
  GC.disable
  yield  # warmup
  times = 3.times.map do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    [elapsed, result]
  end
  GC.enable
  GC.start
  best = times.min_by { |t, _| t }
  best
end

# ============================================================================
# Main
# ============================================================================
puts "=" * 80
puts "N-Body Benchmark (Computer Language Benchmarks Game)"
puts "Ruby #{RUBY_VERSION} (#{RUBY_DESCRIPTION.split(" ")[0..3].join(" ")})"
puts "=" * 80
puts

# Compile
print "Compiling native code... "
bundle_path = compile_native
require bundle_path
$native_obj = Object.new
puts "done"
puts

# Correctness check (small n)
print "Verifying correctness (n=1000)... "
ruby_energy = PureRuby.run(1000)
native_energy = $native_obj.send(:nbody_run, 1000)
diff = (ruby_energy - native_energy).abs
if diff < 1e-9
  puts "OK (diff=#{diff})"
else
  puts "MISMATCH!"
  puts "  Ruby:   #{ruby_energy}"
  puts "  Native: #{native_energy}"
  puts "  Diff:   #{diff}"
end
puts

# Benchmark
[50_000, 500_000, 5_000_000].each do |n|
  puts "-" * 80
  puts "n = #{n}"
  puts "-" * 80

  ruby_time, ruby_result = measure_time { PureRuby.run(n) }
  native_time, native_result = measure_time { $native_obj.send(:nbody_run, n) }

  speedup = ruby_time / native_time
  printf "  Ruby:   %9.4fs  energy=%.9f\n", ruby_time, ruby_result
  printf "  Native: %9.4fs  energy=%.9f\n", native_time, native_result
  printf "  Speedup: %.2fx\n", speedup
  puts
end

puts "=" * 80
puts "Reference: benchmarksgame n-body"
puts "  Initial energy: -0.169075164"
puts "  n=50000000:     -0.169059907"
puts "=" * 80

# Cleanup
File.unlink(bundle_path) rescue nil
