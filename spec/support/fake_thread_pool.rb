# encoding: utf-8

class FakeThreadPool
  attr_accessor :auto_run

  def initialize(auto_run=false)
    @auto_run = auto_run
    @tasks = []
  end

  def run_all
    until @tasks.empty?
      task, promise = @tasks.shift
      promise.try { task.call }
    end
  end

  def submit(&task)
    if @auto_run
      begin
        Ione::Future.resolved(task.call)
      rescue => e
        Ione::Future.failed(e)
      end
    else
      promise = Ione::Promise.new
      @tasks << [task, promise]
      promise.future
    end
  end
end
