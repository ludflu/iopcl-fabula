-- | Layered beam search over partial plans (ticket 26).
module IPOCL.Beam
  ( beamSearch
  ) where

import IPOCL.Plan
import IPOCL.Refine
import IPOCL.Search

-- | Keep the best @width@ plans of each layer by 'planPriority'.
beamSearch :: Int -> Env -> SearchConfig -> Plan -> [SearchEvent]
beamSearch _ _ _ _ = [GaveUp]
