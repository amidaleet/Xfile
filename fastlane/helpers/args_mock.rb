class ArgsMock
  attr_accessor :values

  def initialize(hash)
    @values = hash
  end

  def method_missing(method_sym, *arguments, &)
    @values.fetch(method_sym)
  end

  def respond_to_missing?
    true
  end
end
