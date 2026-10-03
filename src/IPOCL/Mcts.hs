-- | Monte Carlo tree search (UCT) over partial plans (ticket 27).
module IPOCL.Mcts
  ( mctsSearch
  ) where

import IPOCL.Plan
import IPOCL.Refine
import IPOCL.Search

mctsSearch :: MctsParams -> Env -> SearchConfig -> Plan -> [SearchEvent]
mctsSearch _ _ _ _ = [GaveUp]
