# encoding: utf-8

module Ione
  # A null implementation of a thread pool whose {#submit} calls the given block
  # immediately and returns a future resolved with its value.
  #
  # @private
  class NullThreadPool
    # @return [Ione::Future] a future that resolves to the value of the given block
    def submit(&task)
      Future.resolved(task.call)
    rescue => e
      Future.failed(e)
    end
  end

  NULL_THREAD_POOL = NullThreadPool.new
end
