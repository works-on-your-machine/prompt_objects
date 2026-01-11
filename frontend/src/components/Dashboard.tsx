import { usePromptObjects } from '../store'
import { POCard } from './POCard'

export function Dashboard() {
  const promptObjects = usePromptObjects()

  if (promptObjects.length === 0) {
    return (
      <div className="h-full flex items-center justify-center text-gray-500">
        <div className="text-center">
          <div className="text-4xl mb-4">🔮</div>
          <div className="text-lg">No Prompt Objects loaded</div>
          <div className="text-sm mt-2">
            Waiting for environment to connect...
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="h-full overflow-auto p-6">
      <h1 className="text-2xl font-semibold text-white mb-6">
        Prompt Objects
      </h1>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        {promptObjects.map((po) => (
          <POCard key={po.name} po={po} />
        ))}
      </div>
    </div>
  )
}
