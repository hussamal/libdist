-module(libdist_utils).
-export([
      ipn/2,
      cast/3,
      multicast/3,
      call/4,
      anycall/4,
      multicall/4,
      multicall/5
   ]).

-include("libdist.hrl").

% return the {Index, Previous, Next} elements of a chain member
% the previous of the first chain member is chain_head
% the next of the last chain member is chain_tail
ipn(Pid, Chain) ->
   ipn(Pid, Chain, 1).
ipn(Pid, [Pid, Next | _], 1) -> {1, chain_head, Next};
ipn(Pid, [Prev, Pid, Next | _], Index) -> {Index + 1, Prev, Next};
ipn(Pid, [Prev, Pid], Index) -> {Index + 1, Prev, chain_tail};
ipn(Pid, [_ | Tail], Index) -> ipn(Pid, Tail, Index + 1).


% send an asynchronous request to the given process
% returns the request's reference
cast(Pid, Tag, Request) ->
   Ref = make_ref(),
   Pid ! {Ref, self(), Tag, Request},
   Ref.


% send an asynchronous request to all the processes of a list
% returns the request's reference
multicast(Pids, Tag, Request) ->
   Ref = make_ref(),
   Self = self(),
   % spawn separate processes to send in parallel
   [ spawn(fun() -> Pid ! {Ref, Self, Tag, Request} end) || Pid <- Pids ],
   Ref.


% send synchronous request to a process
call(Pid, Tag, Request, Retry) ->
   call(Pid, make_ref(), Tag, Request, Retry).


% send parallel requests to all processes in a list and wait for one response
anycall(Pids, Tag, Request, Retry) ->
   multicall(Pids, Tag, Request, 1, Retry).


% send parallel requests to all processes in a list and wait for all responses
multicall(Pids, Tag, Request, Retry) ->
   multicall(Pids, Tag, Request, length(Pids), Retry).


% send parallel requests to all processes and wait to get NumResponses responses
multicall(Pids, Tag, Request, NumResponses, Retry) ->
   Parent = self(),
   Ref = make_ref(),
   % spawn a collector process so that parent's inbox isn't jammed with unwanted
   % messages beyond the required NumResponses
   % FIXME: this is less efficient than just using the existing process
   spawn(fun() ->
            Collector = self(),
            % create a sub-process for each Pid to make a call
            [spawn(fun() ->
                     Collector ! {Ref, Pid, call(Pid, Ref, Tag, Request, Retry)}
                  end) || Pid <- Pids],
            Parent ! {Ref, collectMany(Ref, [], NumResponses)}
      end),
   % wait for a response from the collector
   receive
      {Ref, Results} -> Results
   end.


%%%%%%%%%%%%%%%%%%%%%
% Private Functions %
%%%%%%%%%%%%%%%%%%%%%


% send synchronous request to a given Pid
call(Pid, Ref, Tag, Request, RetryAfter) ->
   Pid ! {Ref, self(), Tag, Request},
   receive
      {Ref, Result} -> Result
   after
      RetryAfter -> call(Pid, Ref, Tag, Request, RetryAfter)
   end.


% Collect a required number of responses and return them
collectMany(_Ref, Responses, Required) when length(Responses) == Required ->
   Responses;
collectMany(Ref, Responses, Required) ->
   receive
      {Ref, Pid, Result} ->
         NewResponses = [ {Pid, Result} | lists:keydelete(Pid, 1, Responses) ],
         collectMany(Ref, NewResponses, Required);

      _ ->  % ignore old messages
         collectMany(Ref, Responses, Required)
   end.
