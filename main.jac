"""Cirql — entry point.

Server: schema.sv.jac (nodes/edges) and walkers.sv.jac (API).
Client: frontend.cl.jac + frontend.impl.jac, components/, pages/.
See AGENTS.md for ownership and workflow.
"""

import from walkers { Ping, GetMe, ListPeople, ListGoals, DevAddPerson }
import from onboard { OnboardMe }
import from gate { GateMyRoot, GatePostShared, GateListShared, GateMakeCard, GateReadCard }
import from capture { Capture }
import from gaps { GapFinder, GapDevSeed }
import from goals { GoalRank, SetGoal, CloseGoal }
import from scoring { ScoreAgainstNeed }
import from intros { AdvanceIntroduction, DevProposeIntroduction }
import from exchange { PostRequest, ListIncomingRequests, ReplyToRequest, ListMyRequests, ApproveReply, OptIn, Reveal, ClaimReveal, DeclineRequest, DeclineReply, DevMakeCard, DevSeedMatch }
import from cards { PublishCard, get_card }
import from reads { Receipt, ListPromises, CompletePromise, GraphView }
import from imports { ImportPeople, ConfirmPerson, SkipPerson }

# Client-side UI
cl {
    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
