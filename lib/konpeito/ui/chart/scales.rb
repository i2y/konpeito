# Chart Scales - domain-to-pixel coordinate mapping
# Pure math classes, no UI dependency
# IMPORTANT: In constructors, use local params (not @field) to avoid JVM field type issues

class LinearScale
  def initialize(domain_min, domain_max, range_min, range_max)
    @domain_min = domain_min
    @domain_max = domain_max
    @range_min = range_min
    @range_max = range_max
    span = domain_max - domain_min
    if span == 0.0
      @factor = 0.0
    else
      @factor = (range_max - range_min) / span
    end
  end

  def map(value)
    @range_min + (value - @domain_min) * @factor
  end

  def domain_min
    @domain_min
  end

  def domain_max
    @domain_max
  end

  def range_min
    @range_min
  end

  def range_max
    @range_max
  end
end

class BandScale
  def initialize(count, range_min, range_max, padding)
    @count = count
    @range_min = range_min
    @range_max = range_max
    @padding = padding
    total = range_max - range_min
    @band_width = compute_band_width(count, total, padding)
  end

  def compute_band_width(count, total, padding)
    if count > 0.0
      slots = count + 1.0
      pad_total = padding * slots
      usable = total - pad_total
      bw = usable / count
      if bw < 1.0
        bw = 1.0
      end
      bw
    else
      total
    end
  end

  def map(index)
    idx = index * 1.0
    @range_min + @padding + idx * (@band_width + @padding)
  end

  def band_width
    @band_width
  end

  def count
    @count
  end
end
