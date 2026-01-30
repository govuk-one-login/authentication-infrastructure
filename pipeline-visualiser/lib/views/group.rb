class Group
  attr_accessor :name, :pipelines

  def initialize(name, pipelines)
    @name = name
    @pipelines = pipelines
  end
end
