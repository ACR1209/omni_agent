class User
  RECORDS = {
    "1" => { name: "Alice" },
    "42" => { name: "Bob" }
  }.freeze

  attr_reader :id, :name

  def self.find(id)
    record = RECORDS[id.to_s]
    raise ArgumentError, "User #{id} not found" unless record

    new(id.to_s, record[:name])
  end

  def initialize(id, name)
    @id = id
    @name = name
  end
end
