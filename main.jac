"""Cirql — entry point.

Server: schema.sv.jac (nodes/edges) and walkers.sv.jac (API).
Client: frontend.cl.jac + frontend.impl.jac, components/, pages/.
See AGENTS.md for ownership and workflow.
"""

import from walkers { Ping, GetMe, ListPeople, ListGoals, DevAddPerson }
import from onboard { OnboardMe }
import from gate { GateMyRoot, GatePostShared, GateListShared, GateMakeCard, GateReadCard }
import from walkers { Ping, GetMe, ListPeople, ListGoals }
import from capture { Capture }

# Client-side UI
cl {
    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
