class String
  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end

  def resource_safe
    self.gsub(/[^a-zA-Z0-9]/, "").capitalize
  end

  def event_id_safe
    self.gsub('*', 'wildcard').gsub(/[^\.\-_A-Za-z0-9]+/, "").downcase
  end

  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def green
    colorize(32)
  end

  def yellow
    colorize(33)
  end
end